#!/usr/bin/env bash
# Black-box tests for skills/openspec-orchestrator/scripts/run-change through its CLI interface only.
# Substitutes both seams: OPENSPEC_STORE_REGISTRY -> temp registry,
# --project -> temp git clone of a temp bare origin.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
SKILL=skills/openspec-orchestrator
RC=$SKILL/scripts/run-change

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export OPENSPEC_STORE_REGISTRY="$TMP/registry.yaml"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

STORE="$TMP/store"
mkdir -p "$STORE/openspec"
cat > "$OPENSPEC_STORE_REGISTRY" <<EOF
stores:
  teststore:
    local_path: $STORE
EOF
# single rule: orchestration config lives in the store, never in the project
cat > "$STORE/openspec/config.yaml" <<'EOF'
orchestration:
  concurrency: 2
  unit_concurrency: 2
  gate_quick: "echo QUICK-OK in $PWD"
  gate_full: "echo FULL-OK in $PWD"
EOF

git init -q --bare -b main "$TMP/origin"
git clone -q "$TMP/origin" "$TMP/project"
PROJECT="$TMP/project"
echo hello > "$PROJECT/README"
git -C "$PROJECT" add -A && git -C "$PROJECT" commit -qm init && git -C "$PROJECT" push -q origin main

fails=0
check() { # check <desc> <cmd...>
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then echo "ok   $desc"; else echo "FAIL $desc"; fails=$((fails+1)); fi
}
check_out() { # check_out <desc> <expected-substring> <cmd...>
  local desc="$1" want="$2"; shift 2
  local out; out="$("$@" 2>&1)" || { echo "FAIL $desc (exit)"; fails=$((fails+1)); return; }
  case "$out" in *"$want"*) echo "ok   $desc" ;; *) echo "FAIL $desc (got: $out)"; fails=$((fails+1)) ;; esac
}
check_line() { # check_line <desc> <expected-exact-line> <cmd...> -- asserts
  # one of the command's output lines equals <expected-exact-line> exactly,
  # so a substring like "ready: " cannot pass against "ready: b".
  local desc="$1" want="$2"; shift 2
  local out; out="$("$@" 2>&1)" || { echo "FAIL $desc (exit)"; fails=$((fails+1)); return; }
  local line found=""
  while IFS= read -r line; do
    [ "$line" = "$want" ] && { found=1; break; }
  done <<EOF_LINES
$out
EOF_LINES
  if [ -n "$found" ]; then echo "ok   $desc"; else echo "FAIL $desc (got: $out)"; fails=$((fails+1)); fi
}
line_of() { # line_of <exact-line-or-prefix> <text> -> 1-based number of the
  # first line of <text> starting with it, empty if none
  printf '%s\n' "$2" | { grep -nF -- "$1" || true; } | while IFS=: read -r n l; do
    case "$l" in "$1"*) echo "$n"; break ;; esac
  done
}

# syntax first: a parse error would make every check below fail for the
# same reason, so stop here instead of drowning it in noise.
check "run-change parses" bash -n $SKILL/scripts/run-change
check "lib.sh parses" bash -n $SKILL/scripts/lib.sh
check "run.sh parses" bash -n tests/run.sh
[ "$fails" -eq 0 ] || { echo "syntax errors — not running behavior tests"; exit 1; }

# dead-code pass (the bash stand-in for knip): every function defined in the
# engine must be referenced somewhere other than its own definition.
dead=""
for fn in $(grep -ohE '^[a-z_]+\(\)' $SKILL/scripts/lib.sh $SKILL/scripts/run-change | tr -d '()'); do
  if ! grep -hE "\b$fn\b" $SKILL/scripts/lib.sh $SKILL/scripts/run-change tests/run.sh | grep -qvE "^$fn\(\)"; then
    dead="$dead $fn"
  fi
done
check "no engine function without a caller${dead:+ (dead:$dead)}" test -z "$dead"

# state
check "state init creates file" $RC state init --store teststore --name feat-a
check_out "state get returns phase" "phase: proposed" $RC state get --store teststore --name feat-a
check_out "state init has empty acceptance" 'acceptance: ""' $RC state get --store teststore --name feat-a
check_out "state init has full lifecycle" "lifecycle: full" $RC state get --store teststore --name feat-a
check_out "state init has empty manual_tasks_open" 'manual_tasks_open: ""' $RC state get --store teststore --name feat-a
check_out "state init has empty manual_accept" 'manual_accept: ""' $RC state get --store teststore --name feat-a
$RC state set --store teststore --name feat-a phase applying blocked_on fix-b
check_out "state set updates phase" "phase: applying" $RC state get --store teststore --name feat-a
check_out "state set upserts new-style pair" "blocked_on: fix-b" $RC state get --store teststore --name feat-a
$RC state set --store teststore --name feat-a seams "auth=src/auth/session.ts,src/auth/token.ts;billing=src/billing/invoice.ts"
check_out "state set stores seam list" "auth=src/auth/session.ts,src/auth/token.ts;billing=src/billing/invoice.ts" $RC state get --store teststore --name feat-a
created="$(grep '^created_at:' "$STORE/.orchestration/state/feat-a.yaml")"
updated="$(grep '^updated_at:' "$STORE/.orchestration/state/feat-a.yaml")"
[ "${created#created_at:}" != "${updated#updated_at:}" ] || sleep 1
$RC state set --store teststore --name feat-a phase checking
updated2="$(grep '^updated_at:' "$STORE/.orchestration/state/feat-a.yaml")"
if [ "$updated2" != "created_at:${created#created_at:}" ] && [ -n "${updated2#updated_at: }" ]; then
  echo "ok   state set refreshes updated_at"
else
  echo "FAIL state set refreshes updated_at"; fails=$((fails+1))
fi

# session log
check_out "session list empty before any append" "" $RC session list --store teststore --name feat-a
$RC session append --store teststore --name feat-a role worker phase applying tier mechanical model haiku-4.5 transcript_id t1
$RC session append --store teststore --name feat-a role worker phase checking tier deep model opus-5 transcript_id t2
check_out "session list shows first entry" "tier=mechanical model=haiku-4.5" $RC session list --store teststore --name feat-a
check_out "session list shows second entry" "tier=deep model=opus-5" $RC session list --store teststore --name feat-a
lines="$($RC session list --store teststore --name feat-a | wc -l | tr -d ' ')"
[ "$lines" = "2" ] && echo "ok   session log appends, never rewrites" || { echo "FAIL session log appends, never rewrites (got $lines lines)"; fails=$((fails+1)); }

# status
check_out "status lists change" "feat-a" $RC status --store teststore
check_out "status shows phase" "checking" $RC status --store teststore
check_out "status shows last session tier" "deep" $RC status --store teststore
check_out "status shows advisor calls against cap" "0/2" $RC status --store teststore
# advisor cap is enforced by the engine, not just displayed
check_out "direct session append of role advisor is refused" "reserved" bash -c "$RC session append --store teststore --name feat-a role advisor tier deep model x 2>&1; true"
check_out "advisor request grants and prints deep model" "claude-opus-5" $RC advisor request --store teststore --name feat-a --worker w1
check_out "status counts advisor calls" "1/2" $RC status --store teststore
check_out "second request from same worker refused" "already used its one advisor call" bash -c "$RC advisor request --store teststore --name feat-a --worker w1 2>&1; true"
check_out "request from another worker granted" "claude-opus-5" $RC advisor request --store teststore --name feat-a --worker w2
check_out "third request hits the per-change cap" "advisor cap reached" bash -c "$RC advisor request --store teststore --name feat-a --worker w3 2>&1; true"
check_out "status shows cap reached" "2/2" $RC status --store teststore
check_out "advisor entry records the asking worker" "role=advisor tier=deep model=claude-opus-5 for=w1" $RC session list --store teststore --name feat-a

# slots (cap=2 from store config)
s1="$($RC slot acquire --store teststore --project "$PROJECT")"
s2="$($RC slot acquire --store teststore --project "$PROJECT")"
check_out "third slot refused at cap" "no free slot" bash -c "$RC slot acquire --store teststore --project '$PROJECT' 2>&1; true"
$RC slot release --store teststore --slot "$s1"
check "released slot reusable" $RC slot acquire --store teststore --project "$PROJECT"
$RC slot release --store teststore --slot "$s1"
$RC slot release --store teststore --slot "$s2"

# workspace
wt="$($RC workspace create --store teststore --project "$PROJECT" --name feat-a)"
check "workspace worktree exists" git -C "$wt" rev-parse --is-inside-work-tree
check "workspace branch exists" git -C "$PROJECT" rev-parse --verify change/feat-a
check "workspace lives under the store, not the project" test "$wt" = "$STORE/.orchestration/workspaces/feat-a"
check "project checkout has no untracked workspace dir" bash -c "[ -z \"\$(git -C '$PROJECT' status --porcelain)\" ]"
check_out "store ignores its workspaces dir" ".orchestration/workspaces/" cat "$STORE/.gitignore"
$RC workspace create --store teststore --project "$PROJECT" --name feat-dup >/dev/null 2>&1
check "gitignore entry not duplicated" test "$(grep -c '.orchestration/workspaces/' "$STORE/.gitignore")" = 1
$RC workspace remove --store teststore --project "$PROJECT" --name feat-dup
# gate runs in the change's worktree, never the project's main checkout
check_out "quick gate runs in the worktree" "QUICK-OK in $wt" $RC gate run --store teststore --project "$PROJECT" --name feat-a --mode quick
check_out "quick gate does not record gate_tree" 'gate_tree: ""' $RC state get --store teststore --name feat-a
check_out "full gate runs in the worktree" "FULL-OK in $wt" $RC gate run --store teststore --project "$PROJECT" --name feat-a --mode full
check "passing full gate records the tree it ran on" bash -c "grep -qE '^gate_tree: [0-9a-f]{40}\$' '$STORE/.orchestration/state/feat-a.yaml'"
check_out "gate run without a workspace errors" "no workspace for change" bash -c "$RC gate run --store teststore --project '$PROJECT' --name feat-none --mode quick 2>&1; true"
$RC workspace remove --store teststore --project "$PROJECT" --name feat-a
check "workspace removed" test ! -e "$wt"
check "branch removed" bash -c "! git -C '$PROJECT' rev-parse --verify -q change/feat-a"

# gates (config read from the store, project has no openspec/)

# tier -> model
check_out "model get falls back to default for mechanical" "claude-haiku-4-5-20251001" $RC model get --store teststore --tier mechanical
check_out "model get falls back to default for deep" "claude-opus-5" $RC model get --store teststore --tier deep
cat >> "$STORE/openspec/config.yaml" <<'EOF'
  model_deep: "claude-opus-5-custom"
EOF
check_out "model get honors store override" "claude-opus-5-custom" $RC model get --store teststore --tier deep

# stage -> project skill(s) (docs/proposals/skill-stage-mapping.md)
check_out "stage-skills get is empty when stage_skills is unset" "" $RC stage-skills get --store teststore --stage plan

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

# role overlays: <store>/openspec/roles/<role>.md, text printed verbatim
check_out "roles get with no overlay prints nothing" "" $RC roles get --store teststore --role critic
check "roles get with no overlay exits 0" $RC roles get --store teststore --role critic
check_out "roles get refuses an unknown role" "unknown role" bash -c "$RC roles get --store teststore --role reviewer 2>&1; true"
check "roles get with an unknown role exits non-zero" bash -c "! $RC roles get --store teststore --role reviewer >/dev/null 2>&1"
check "roles prompt with no overlay exits 0" $RC roles prompt --store teststore --role verifier
check "roles prompt with no overlay prints exactly the engine prompt" bash -c "diff <($RC roles prompt --store teststore --role verifier) $SKILL/scripts/roles/verifier.md"
check_out "roles prompt refuses an unknown role" "unknown role" bash -c "$RC roles prompt --store teststore --role reviewer 2>&1; true"
check "roles prompt with an unknown role exits non-zero" bash -c "! $RC roles prompt --store teststore --role reviewer >/dev/null 2>&1"
mkdir -p "$STORE/openspec/roles"
printf 'Check every scenario in the delta spec has a named test.\n' > "$STORE/openspec/roles/critic.md"
printf 'Run tests with ./tests/run.sh; a red check prints FAIL.\n' > "$STORE/openspec/roles/worker.md"
check_out "roles get prints the overlay text" "named test" $RC roles get --store teststore --role critic
check_out "roles get is per role" "FAIL" $RC roles get --store teststore --role worker
rp_out="$($RC roles prompt --store teststore --role critic 2>/dev/null || true)"
rp_last="$(line_of "$(tail -n1 $SKILL/scripts/roles/critic.md 2>/dev/null || true)" "$rp_out")"
rp_ov="$(line_of "$(head -n1 "$STORE/openspec/roles/critic.md")" "$rp_out")"
check "roles prompt prints the engine prompt's last line before the overlay's first" test "${rp_last:-999}" -lt "${rp_ov:-0}"
check "roles get with an overlay still prints only the overlay text" test "$($RC roles get --store teststore --role critic)" = "$(cat "$STORE/openspec/roles/critic.md")"
cat >> "$STORE/openspec/config.yaml" <<'EOF'
  stage_skills:
    plan: project-spec-drafter
    critic: [project-code-review]
    test: [project-test-skill, project-contract-checker]
EOF
check_out "stage-skills get returns the single plan skill" "project-spec-drafter" $RC stage-skills get --store teststore --stage plan
check_out "stage-skills get returns a one-item critic list" "project-code-review" $RC stage-skills get --store teststore --stage critic
out="$($RC stage-skills get --store teststore --stage test)"
check "stage-skills get returns both test-stage skills" test "$out" = "project-test-skill
project-contract-checker"
check_out "stage-skills get is empty for an unmapped stage" "" $RC stage-skills get --store teststore --stage apply

# generator/checker split: the checker is one tier above the generator
check_out "model get knows the max tier" "claude-fable-5-1" $RC model get --store teststore --tier max
check_out "model verify with no history assumes a standard implementer -> deep" "claude-opus-5-custom" $RC model verify --store teststore --name feat-verify
$RC session append --store teststore --name feat-verify role worker phase applying tier standard model claude-sonnet-5 transcript_id t1
check_out "model verify picks the tier above the implementer" "claude-opus-5-custom" $RC model verify --store teststore --name feat-verify
check_out "model verify contract names the store/name/seams field" "--store teststore --name feat-verify, field seams" $RC model verify --store teststore --name feat-verify
check_out "model verify first line is the bare model id" "claude-opus-5-custom" bash -c "$RC model verify --store teststore --name feat-verify | head -n1"
check_out "model verify contract mentions input and seam" "input:" $RC model verify --store teststore --name feat-verify
check_out "model verify contract names the store config as an input" "$STORE/openspec/config.yaml" $RC model verify --store teststore --name feat-verify
check_out "model verify contract makes a stale config a warning" "else one warning finding" $RC model verify --store teststore --name feat-verify
check "model verify contract names no Project glossary or ADRs" bash -c "out=\"\$($RC model verify --store teststore --name feat-verify)\" && case \"\$out\" in *openspec/CONTEXT.md*|*openspec/adr/*) exit 1 ;; esac"
out_cc="$($RC model critic --store teststore --name feat-critic 2>/dev/null || true)"
case "$out_cc" in *"config.yaml"*) echo "FAIL model critic contract does not name the store config"; fails=$((fails+1)) ;; *) echo "ok   model critic contract does not name the store config" ;; esac
$RC session append --store teststore --name feat-infer role worker phase applying model claude-sonnet-5 transcript_id t1
check_out "model verify infers the tier from the model when an entry has none" "claude-opus-5-custom" $RC model verify --store teststore --name feat-infer
cat >> "$STORE/openspec/config.yaml" <<'EOF'
  model_standard: "claude-opus-5-custom"
EOF
check_out "model verify errors when a tier-less entry's model maps to no tier" "cannot tell which tier" bash -c "$RC model verify --store teststore --name feat-infer 2>&1; true"
$RC session append --store teststore --name feat-verify role worker phase applying tier deep model claude-opus-5-custom transcript_id t2
check_out "model verify for a deep implementer goes to max" "claude-fable-5-1" $RC model verify --store teststore --name feat-verify
cat >> "$STORE/openspec/config.yaml" <<'EOF'
  model_max: "claude-opus-5-custom"
EOF
check_out "model verify errors when the tier above resolves to the implementer's model" "resolves to the implementer's own model" bash -c "$RC model verify --store teststore --name feat-verify 2>&1; true"

# generator/checker split at Propose: the critic is one tier above the proposer
$RC state init --store teststore --name feat-critic
check_out "state init has propose_rounds" "propose_rounds: 0" $RC state get --store teststore --name feat-critic
$RC session append --store teststore --name feat-critic role worker phase proposed tier deep model claude-opus-5-custom transcript_id t1
check_out "model critic errors when max resolves to the proposer's model" "resolves to the proposer's own model" bash -c "$RC model critic --store teststore --name feat-critic 2>&1; true"
$RC session append --store teststore --name feat-critic role worker phase proposed tier deep model some-other-model transcript_id t2
check_out "model critic uses max for a deep proposer" "claude-opus-5-custom" $RC model critic --store teststore --name feat-critic
$RC session append --store teststore --name feat-critic role worker phase applying tier standard model claude-opus-5-custom transcript_id t3
check_out "model critic ignores non-proposed entries" "claude-opus-5-custom" $RC model critic --store teststore --name feat-critic
$RC session append --store teststore --name feat-critic role worker phase proposed tier max model claude-fable-5-1 transcript_id t4
check_out "model critic for a max proposer drops to deep, the second highest" "claude-opus-5-custom" $RC model critic --store teststore --name feat-critic
$RC session append --store teststore --name feat-critic role worker phase proposed tier max model claude-opus-5-custom transcript_id t5
check_out "model critic errors when deep resolves to a max proposer's model" "resolves to the proposer's own model" bash -c "$RC model critic --store teststore --name feat-critic 2>&1; true"
$RC session append --store teststore --name feat-critic role worker phase proposed tier standard model claude-sonnet-5 transcript_id t6
check_out "model critic first line is the bare model id" "claude-opus-5-custom" bash -c "$RC model critic --store teststore --name feat-critic | head -n1"
check_out "model critic contract mentions input and seam" "input:" $RC model critic --store teststore --name feat-critic
check_out "model critic contract names the store/name/seams field" "--store teststore --name feat-critic, field seams" $RC model critic --store teststore --name feat-critic
out_cg="$($RC model critic --store teststore --name feat-critic 2>/dev/null || true)"
cg_glos="$(printf '%s\n' "$out_cg" | { grep '^input: the Project glossary' || true; } | head -n1)"
cg_adr="$(printf '%s\n' "$out_cg" | { grep '^input: the ADRs' || true; } | head -n1)"
check_out "model critic contract names the store's Project glossary" "$STORE/openspec/CONTEXT.md" printf '%s\n' "$cg_glos"
check_out "model critic contract names the store's ADR dir" "$STORE/openspec/adr/" printf '%s\n' "$cg_adr"
check_out "model critic contract's ADR line names supersedes" "supersedes" printf '%s\n' "$cg_adr"
cg_seam_n="$(line_of 'input: seam list' "$out_cg")"
cg_glos_n="$(line_of 'input: the Project glossary' "$out_cg")"
cg_adr_n="$(line_of 'input: the ADRs' "$out_cg")"
cg_prior_n="$(line_of 'input: the prior critic report, if any' "$out_cg")"
check "model critic contract lists the glossary between the seam and prior-report lines" \
  bash -c "[ ${cg_seam_n:-999} -lt ${cg_glos_n:-0} ] && [ ${cg_glos_n:-999} -lt ${cg_prior_n:-0} ]"
check "model critic contract lists the ADRs between the seam and prior-report lines" \
  bash -c "[ ${cg_seam_n:-999} -lt ${cg_adr_n:-0} ] && [ ${cg_adr_n:-999} -lt ${cg_prior_n:-0} ]"

# initiatives: own record, own critique-round counter, shown as a tree in status
check "initiative init creates file" $RC initiative init --store teststore --name init-a
check_out "initiative get has critique_rounds" "critique_rounds: 0" $RC initiative get --store teststore --name init-a
$RC initiative set --store teststore --name init-a children feat-a,feat-new critique_rounds 1 last_critique_result blocking:2
check_out "initiative set upserts rounds" "critique_rounds: 1" $RC initiative get --store teststore --name init-a
$RC initiative set --store teststore --name init-a last_critique_result blocking:1
check_out "initiative set shifts prev critique result too" "prev_critique_result: blocking:2" $RC initiative get --store teststore --name init-a
check "initiative is not a change state file" bash -c "! test -f '$STORE/.orchestration/state/init-a.yaml'"
check_out "status shows initiative tree" "init-a" $RC status --store teststore
check_out "status shows started child phase" "feat-a" $RC status --store teststore
check_out "status shows unstarted child" "not-started" $RC status --store teststore
$RC session append --store teststore --name init-a role worker phase proposed tier deep model claude-opus-5-custom transcript_id t9
check_out "model critic works for an initiative name" "resolves to the proposer's own model" bash -c "$RC model critic --store teststore --name init-a 2>&1; true"
$RC session append --store teststore --name init-a role worker phase proposed tier deep model claude-opus-5-other transcript_id t10
check_out "model critic for an initiative (no change state file) prints the contract" "input:" $RC model critic --store teststore --name init-a
check_out "initiative merged refuses unlisted child" "not a child" bash -c "$RC initiative merged --store teststore --name init-a --child feat-zzz --commit abc 2>&1; true"
$RC initiative merged --store teststore --name init-a --child feat-a --commit abc1234
check_out "initiative merged records sha" "merged: feat-a=abc1234" $RC initiative get --store teststore --name init-a
$RC initiative merged --store teststore --name init-a --child feat-new --commit def5678
$RC initiative merged --store teststore --name init-a --child feat-a --commit aaa0000
check_out "initiative merged upserts and keeps order" "merged: feat-a=aaa0000,feat-new=def5678" $RC initiative get --store teststore --name init-a
check_out "status shows merged child with sha" "aaa0000" $RC status --store teststore

# lifecycle field: empty reads as full (exercised throughout below); any
# other value is refused outright
$RC state init --store teststore --name feat-bogus-lifecycle
$RC state set --store teststore --name feat-bogus-lifecycle lifecycle bogus
check_out "next: unknown lifecycle errors" "unknown lifecycle" bash -c "$RC next --store teststore --name feat-bogus-lifecycle 2>&1; true"

# next: the orchestration policy as code — walk a change through the lifecycle
N="$RC next --store teststore --name feat-next"
$RC state init --store teststore --name feat-next
check_out "state init seeds pillars and grill" "pillars: \"\"" $RC state get --store teststore --name feat-next
check_out "next: fresh change -> classify first" "action: classify" $N
check_out "next: classify runs at standard" "tier: standard" $N
check_out "next: classify names the pillar vocabulary" "scope=file|seam|seams;blast=none|project|public;novelty=known|new;deps=none|dev|runtime" $N
check_line "next: classify prints the proposer prompt" "prompt: $PWD/$SKILL/scripts/roles/proposer.md" $N
$RC state set --store teststore --name feat-next pillars "scope=seam;blast=none;novelty=huge;deps=none"
check_out "next: unknown pillar value is refused" "unknown novelty 'huge'" bash -c "$N 2>&1; true"
$RC state set --store teststore --name feat-next pillars "scope=seam;blast=none;novelty=known"
check_out "next: missing pillar is refused" "missing 'deps'" bash -c "$N 2>&1; true"
$RC state set --store teststore --name feat-next pillars "scope=seam;blast=none;novelty=known;deps=none"
check_out "next: trivial on every pillar -> propose, grill skipped" "action: propose" $N
check_out "next: trivial reason says grill skipped" "grill mode skipped" $N
$RC state set --store teststore --name feat-next pillars "scope=file;blast=none;novelty=known;deps=none"
check_out "next: one file is trivial too" "action: propose" $N
$RC state set --store teststore --name feat-next pillars "scope=seams;blast=project;novelty=new;deps=runtime"
check_out "next: non-trivial and not grilled -> grill" "action: grill" $N
check_out "next: grill is tier none" "tier: none" $N
check_out "next: grill reason says autonomy starts after it" "Autonomy starts after this" $N
out_grill="$($N)"
case "$out_grill" in *"prompt:"*) echo "FAIL next: grill prints no role prompt"; fails=$((fails+1)) ;; *) echo "ok   next: grill prints no role prompt" ;; esac
$RC state set --store teststore --name feat-next pillars "scope=seam;blast=none;novelty=new;deps=none"
check_out "next: a single pillar above trivial is enough for grill" "action: grill" $N
$RC state set --store teststore --name feat-next grill skipped:human
check_out "next: human-recorded skip -> propose" "action: propose" $N
$RC state set --store teststore --name feat-next grill done pillars "scope=seams;blast=project;novelty=new;deps=runtime"
check_out "next: grilled change -> propose at deep" "action: propose" $N
check_out "next: propose reason cites the glossary and ADRs" "Project glossary and ADRs" $N
check_out "next: propose model is deep" "model: claude-opus-5-custom" $N
check_line "next: propose prints the engine proposer prompt" "prompt: $PWD/$SKILL/scripts/roles/proposer.md" $N
out_pr="$($N)"
case "$out_pr" in *"overlay:"*) echo "FAIL next: propose prints no overlay without a proposer overlay"; fails=$((fails+1)) ;; *) echo "ok   next: propose prints no overlay without a proposer overlay" ;; esac
$RC session append --store teststore --name feat-next role worker phase proposed tier deep model claude-opus-5-plain transcript_id p1
check_out "next: draft exists -> critique" "action: critique" $N
check_out "next: critique of a deep draft runs at max" "tier: max" $N
check_out "next: critique names the store's critic overlay" "overlay: $STORE/openspec/roles/critic.md" $N
check_line "next: critique prints the engine critic prompt" "prompt: $PWD/$SKILL/scripts/roles/critic.md" $N
out_cr="$($N)"
cr_reason="$(line_of reason: "$out_cr")"; cr_prompt="$(line_of prompt: "$out_cr")"; cr_ov="$(line_of overlay: "$out_cr")"
check "next: critique prompt: is the line right after reason:" test "${cr_prompt:-x}" = "$(( ${cr_reason:-0} + 1 ))"
check "next: critique prompt: precedes overlay:" test "${cr_prompt:-999}" -lt "${cr_ov:-0}"
$RC session append --store teststore --name feat-next role worker phase proposed tier max model claude-fable-5-1 transcript_id p2
check_out "next: critique of a max draft runs at deep" "tier: deep" $N
$RC state set --store teststore --name feat-next last_critique_result blocking:2
check_out "next: blocking critique -> revise round 1" "action: revise" $N
$RC state set --store teststore --name feat-next last_critique_result blocking:2
check_out "next: critique count unchanged -> gate1 not converging" "critique not converging" $N
$RC state set --store teststore --name feat-next last_critique_result blocking:1
check_out "next: critique count fell -> revise" "action: revise" $N
$RC state set --store teststore --name feat-next propose_rounds 2
check_out "next: blocking critique at cap -> gate1" "action: gate1" $N
$RC state set --store teststore --name feat-next last_critique_result request propose_rounds 0
check_out "next: request finding -> gate1" "action: gate1" $N
$RC state set --store teststore --name feat-next last_critique_result warnings:1
check_out "next: critique passed -> gate0" "action: gate0" $N
check_out "next: gate0 sets phase awaiting-acceptance" "set_phase: awaiting-acceptance" $N
check_out "next: gate0 reason names the fast-path option" "fast-path" $N
check_out "next: gate0 reason names light lifecycle" "light lifecycle" $N
$RC state set --store teststore --name feat-next phase awaiting-acceptance
check_out "next: awaiting-acceptance with no answer -> gate0 again" "action: gate0" $N

# Gate 0: a human "revise" answer restarts Propose; a fresh draft naturally
# lands back at critique (proposer_model is no longer empty), then Gate 0
# fires again on the new draft, then "accepted" reaches Apply.
$RC state set --store teststore --name feat-next acceptance revise
check_out "next: human requests changes -> propose (restart)" "action: propose" $N
check_out "next: revise restarts propose at deep" "tier: deep" $N
check_out "next: revise sets phase back to proposed" "set_phase: proposed" $N
$RC state set --store teststore --name feat-next phase proposed acceptance "" last_critique_result "" propose_rounds 0
$RC session append --store teststore --name feat-next role worker phase proposed tier deep model claude-opus-5-plain transcript_id p3
check_out "next: restarted draft exists -> critique again" "action: critique" $N
$RC state set --store teststore --name feat-next last_critique_result clean
check_out "next: second round critique clean -> gate0 again" "action: gate0" $N
$RC state set --store teststore --name feat-next phase awaiting-acceptance acceptance accepted
check_out "next: human accepts -> apply" "action: apply" $N
check_out "next: accept is tier none" "tier: none" $N
check_out "next: accept model is -" "model: -" $N
check_out "next: accept sets phase applying" "set_phase: applying" $N
$RC state set --store teststore --name feat-next phase applying acceptance ""
check_out "next: applying with no units -> split at deep (full, parallel)" "action: split" $N
check_out "next: split tier is deep" "tier: deep" $N
out="$($N)"
case "$out" in *"running:"*) echo "FAIL next: split prints no running: line (got: $out)"; fails=$((fails+1)) ;; *) echo "ok   next: split prints no running: line" ;; esac
# the units lifecycle itself is exercised in its own section below; jump
# this change straight to checking to keep driving the rest of the ladder
$RC state set --store teststore --name feat-next phase checking
check_out "next: checking with no gate result -> check" "action: check" $N
check_out "next: check also dispatches verify concurrently" "also: verify" $N
check_out "next: concurrent verify gets the distinct-model id" "also_model: claude-opus-5-custom" $N
out_chk="$($N)"
case "$out_chk" in *"also_overlay:"*) echo "FAIL next: check prints no also_overlay without a verifier overlay"; fails=$((fails+1)) ;; *) echo "ok   next: check prints no also_overlay without a verifier overlay" ;; esac
check_line "next: check prints the engine verifier prompt for the concurrent Verify" "also_prompt: $PWD/$SKILL/scripts/roles/verifier.md" $N
chk_model="$(line_of also_model: "$out_chk")"; chk_prompt="$(line_of also_prompt: "$out_chk")"
check "next: check also_prompt: is the line right after also_model:" test "${chk_prompt:-x}" = "$(( ${chk_model:-0} + 1 ))"
printf 'Verify the bump in releases.json matches the SKILL.md change.\n' > "$STORE/openspec/roles/verifier.md"
check_out "next: check names the verifier overlay for the concurrent Verify" "also_overlay: $STORE/openspec/roles/verifier.md" $N
$RC state set --store teststore --name feat-next last_gate_result red
check_out "next: red gate -> fix round 1" "action: fix" $N
check_out "next: fix names the worker overlay" "overlay: $STORE/openspec/roles/worker.md" $N
check_out "next: fix round 1 is standard" "tier: standard" $N
$RC state set --store teststore --name feat-next fix_attempts 2
check_out "next: fix round 3 is deep" "tier: deep" $N
$RC state set --store teststore --name feat-next fix_attempts 3
check_out "next: red gate out of rounds -> gate1" "action: gate1" $N
$RC state set --store teststore --name feat-next last_gate_result green fix_attempts 0
check_out "next: green gate unverified -> verify" "action: verify" $N
check_out "next: verify names the verifier overlay" "overlay: $STORE/openspec/roles/verifier.md" $N
$RC session append --store teststore --name feat-next role worker phase applying tier standard model claude-sonnet-5 transcript_id a1
check_out "next: verify model is the tier above the implementer" "model: claude-opus-5-custom" $N
check_out "next: verify of a standard implementer runs at deep" "tier: deep" $N
$RC state set --store teststore --name feat-next last_verify_result blocking:3
check_out "next: blocking verify -> fix round" "action: fix" $N
check_out "next: first blocking result has no prev" "prev_verify_result: \"\"" $RC state get --store teststore --name feat-next
$RC state set --store teststore --name feat-next last_verify_result ""
check_out "next: clearing for recheck shifts last into prev" "prev_verify_result: blocking:3" $RC state get --store teststore --name feat-next
$RC state set --store teststore --name feat-next last_verify_result blocking:1
check_out "next: writing over empty keeps prev" "prev_verify_result: blocking:3" $RC state get --store teststore --name feat-next
check_out "next: falling blocking count converges -> fix" "action: fix" $N
$RC state set --store teststore --name feat-next last_verify_result blocking:1
check_out "next: same blocking count -> gate1 not converging" "verify not converging: blocking:1 -> blocking:1" $N
$RC state set --store teststore --name feat-next last_verify_result blocking:4
check_out "next: rising blocking count -> gate1" "action: gate1" $N
$RC state set --store teststore --name feat-next last_verify_result warnings:3
check_out "next: warnings only -> mechanical sweep" "action: sweep" $N
$RC state set --store teststore --name feat-next last_verify_result spec
check_out "next: spec finding -> gate1" "action: gate1" $N
check_out "next: spec gate1 names spec_amend as the way out" "spec_amend accepted" $N
$RC state set --store teststore --name feat-next spec_amend accepted
check_out "next: accepted spec amendment -> fix" "action: fix" $N
check_out "next: spec amendment fix runs at deep in round 1" "tier: deep" $N
$RC state set --store teststore --name feat-next last_gate_result red
check_out "next: spec amendment fix at deep also under a red gate" "tier: deep" $N
$RC state set --store teststore --name feat-next fix_attempts 3
check_out "next: spec amendment out of rounds -> gate1" "action: gate1" $N
$RC state set --store teststore --name feat-next fix_attempts 0 last_gate_result green spec_amend ""
$RC state set --store teststore --name feat-next last_verify_result clean
check_out "next: verified clean -> tasks-open" "action: tasks-open" $N
out_to="$($N)"
case "$out_to" in *"overlay:"*) echo "FAIL next: a none-tier action prints no overlay"; fails=$((fails+1)) ;; *) echo "ok   next: a none-tier action prints no overlay" ;; esac
case "$out_to" in *"prompt:"*) echo "FAIL next: a none-tier action prints no prompt"; fails=$((fails+1)) ;; *) echo "ok   next: a none-tier action prints no prompt" ;; esac
check_out "next: verified clean sets phase verified" "set_phase: verified" $N

# verified: manual_tasks_open gates archive
$RC state set --store teststore --name feat-next phase verified manual_tasks_open "" manual_accept ""
check_out "next: verified with manual_tasks_open empty (fresh init) -> tasks-open" "action: tasks-open" $N
out="$($N)"
case "$out" in
  *"set_phase"*) echo "FAIL next: verified empty manual_tasks_open emits no set_phase (got: $out)"; fails=$((fails+1)) ;;
  *) echo "ok   next: verified empty manual_tasks_open emits no set_phase" ;;
esac
sed -i.bak '/^manual_tasks_open:/d' "$STORE/.orchestration/state/feat-next.yaml"; rm -f "$STORE/.orchestration/state/feat-next.yaml.bak"
check_out "next: verified with manual_tasks_open line missing (pre-1.3.0 state) -> tasks-open" "action: tasks-open" $N
$RC state set --store teststore --name feat-next manual_tasks_open 2
check_out "next: verified with manual_tasks_open 2 -> gate2-manual" "action: gate2-manual" $N
check_out "next: gate2-manual reason mentions the verify report" "verify report" $N
$RC state set --store teststore --name feat-next manual_accept "accepted:"
check_out "next: manual_accept 'accepted:' with no names errors" "names no requirements" bash -c "$N 2>&1; true"
$RC state set --store teststore --name feat-next manual_accept "accepted:R1"
check_out "next: manual_accept naming requirements -> archive" "action: archive" $N
$RC state set --store teststore --name feat-next manual_tasks_open 2 manual_accept yes
check_out "next: manual_accept not empty or accepted:* errors" "unknown manual_accept" bash -c "$N 2>&1; true"
$RC state set --store teststore --name feat-next manual_tasks_open 0 manual_accept ""
check_out "next: manual_tasks_open 0 -> archive" "action: archive" $N
check_out "next: archive reason says --yes allowed because the count is 0" "recorded manual_tasks_open count is 0" $N
$RC state set --store teststore --name feat-next manual_accept "accepted:R1"
$RC state set --store teststore --name feat-next phase archived
check_out "next: archived -> merge-lane" "action: merge-lane" $N
$RC state set --store teststore --name feat-next phase ready-to-merge
check_out "next: ready-to-merge -> gate2" "action: gate2" $N
check_out "next: ready-to-merge gate2 names accepted unverified requirements" "R1" $N
$RC state set --store teststore --name feat-next phase merged
check_out "next: merged -> done" "action: done" $N
$RC state set --store teststore --name feat-next phase blocked blocked_on feat-dep
check_out "next: blocked -> wait" "blocked on feat-dep" $N
$RC state set --store teststore --name feat-next phase checking last_gate_result purple
check_out "next: unknown gate result errors" "unknown last_gate_result" bash -c "$N 2>&1; true"

# check phase with a verify result already recorded (both ran concurrently)
R="$RC next --store teststore --name feat-red"
$RC state init --store teststore --name feat-red
$RC state set --store teststore --name feat-red phase checking last_gate_result red last_verify_result spec
check_out "next: red gate but verify says spec -> gate1" "action: gate1" $R
$RC state set --store teststore --name feat-red last_verify_result blocking:2
check_out "next: red gate with blocking verify -> one fix round for both" "verify blocking:2" $R
check_out "next: that fix round clears both results" "clear last_gate_result and last_verify_result" $R
$RC state set --store teststore --name feat-red last_verify_result blocking:2
check_out "next: red gate, verify not converging -> gate1" "verify not converging" $R

# light lifecycle: standard-tier drafting, deep critic (unchanged tier
# ladder rule), no sweep round; everything else matches full
L="$RC next --store teststore --name feat-light"
$RC state init --store teststore --name feat-light
$RC state set --store teststore --name feat-light lifecycle light pillars "scope=file;blast=none;novelty=known;deps=none"
check_out "next: light fresh change -> propose at standard" "action: propose" $L
check_out "next: light propose tier is standard" "tier: standard" $L
$RC session append --store teststore --name feat-light role worker phase proposed tier standard model claude-sonnet-5 transcript_id lp1
check_out "next: light draft exists -> critique" "action: critique" $L
check_out "next: light critique of a standard draft runs at deep" "tier: deep" $L
$RC state set --store teststore --name feat-light last_critique_result blocking:2
check_out "next: light blocking critique -> revise at standard" "action: revise" $L
check_out "next: light revise tier is standard" "tier: standard" $L
$RC state set --store teststore --name feat-light last_critique_result clean propose_rounds 0
check_out "next: light clean critique -> gate0" "action: gate0" $L
$RC state set --store teststore --name feat-light phase awaiting-acceptance acceptance revise
check_out "next: light gate0 revise restarts propose at standard" "action: propose" $L
check_out "next: light gate0 revise tier is standard" "tier: standard" $L
$RC state set --store teststore --name feat-light phase checking last_gate_result green last_verify_result warnings:2
check_out "next: light green warnings -> tasks-open (sweep skipped)" "action: tasks-open" $L
check_out "next: light tasks-open sets phase verified" "set_phase: verified" $L
$RC state set --store teststore --name feat-light manual_tasks_open 0 phase ready-to-merge
check_out "next: light ready-to-merge gate2 mentions the unswept verify warnings" "unswept Verify warnings" $L
$RC state set --store teststore --name feat-light phase checking manual_tasks_open "" manual_accept ""
$RC state set --store teststore --name feat-light lifecycle full
check_out "next: the same state under full lifecycle -> sweep" "action: sweep" $L

# a project with its own openspec/ folder is refused when the resolved
# store is a DIFFERENT external root (that combination means the caller
# picked the wrong store for a project that should run in local mode)
mkdir "$PROJECT/openspec"
check_out "slot acquire refuses project with openspec/ against a different store" "refusing" bash -c "$RC slot acquire --store teststore --project '$PROJECT' 2>&1; true"
check_out "workspace create refuses project with openspec/ against a different store" "refusing" bash -c "$RC workspace create --store teststore --project '$PROJECT' --name feat-x 2>&1; true"
check_out "gate run refuses project with openspec/ against a different store" "refusing" bash -c "$RC gate run --store teststore --project '$PROJECT' --name feat-x --mode quick 2>&1; true"
check_out "merge lane refuses project with openspec/ against a different store" "refusing" bash -c "$RC merge-lane run --store teststore --project '$PROJECT' --name feat-x 2>&1; true"

# local mode: a store whose local_path IS the project itself is not refused,
# even though the project has its own openspec/ folder (SKILL.md Step 1)
cat >> "$OPENSPEC_STORE_REGISTRY" <<EOF
  localstore:
    local_path: $PROJECT
EOF
cat > "$PROJECT/openspec/config.yaml" <<'EOF'
orchestration:
  concurrency: 1
  gate_quick: "echo QUICK-OK in $PWD"
  gate_full: "echo FULL-OK in $PWD"
EOF
check "slot acquire allowed when the store's local_path is the project (local mode)" "$RC" slot acquire --store localstore --project "$PROJECT"
$RC slot release --store localstore --slot 1 >/dev/null 2>&1 || true
rmdir "$PROJECT/openspec" 2>/dev/null || rm -rf "$PROJECT/openspec"

# merge lane: merges origin trunk into the change branch, reruns the full gate
# only if the merged tree differs from the one that already passed, releases lock
$RC workspace create --store teststore --project "$PROJECT" --name feat-a >/dev/null 2>&1
check_out "merge lane skips the gate when the tree already passed it" "skipping rerun" $RC merge-lane run --store teststore --project "$PROJECT" --name feat-a
echo moved > "$PROJECT/TRUNK-MOVED" && git -C "$PROJECT" add -A && git -C "$PROJECT" commit -qm trunk-moves && git -C "$PROJECT" push -q origin main
before="$(grep '^gate_tree:' "$STORE/.orchestration/state/feat-a.yaml")"
check_out "merge lane merges trunk and reruns full gate when the tree changed" "FULL-OK in $STORE/.orchestration/workspaces/feat-a" $RC merge-lane run --store teststore --project "$PROJECT" --name feat-a
check "rerun full gate records the new tree" test "$(grep '^gate_tree:' "$STORE/.orchestration/state/feat-a.yaml")" != "$before"

# merge lane on a local-only project (no remote): merges the local trunk
LOCAL="$TMP/local-project"
git init -q -b main "$LOCAL"
echo one > "$LOCAL/README" && git -C "$LOCAL" add -A && git -C "$LOCAL" commit -qm init
$RC workspace create --store teststore --project "$LOCAL" --name feat-local >/dev/null 2>&1
echo two > "$LOCAL/FROM-TRUNK" && git -C "$LOCAL" add -A && git -C "$LOCAL" commit -qm trunk-moves
check_out "merge lane falls back to local trunk without a remote" "FULL-OK" $RC merge-lane run --store teststore --project "$LOCAL" --name feat-local
check "local trunk commit reached the change worktree" test -f "$STORE/.orchestration/workspaces/feat-local/FROM-TRUNK"
$RC workspace remove --store teststore --project "$LOCAL" --name feat-local
# ... and errors clearly when there is no trunk to find at all
NOTRUNK="$TMP/notrunk-project"
git init -q -b trunk "$NOTRUNK"
echo x > "$NOTRUNK/README" && git -C "$NOTRUNK" add -A && git -C "$NOTRUNK" commit -qm init
$RC workspace create --store teststore --project "$NOTRUNK" --name feat-nt >/dev/null 2>&1
check_out "merge lane errors when no trunk is identifiable" "cannot determine trunk" bash -c "$RC merge-lane run --store teststore --project '$NOTRUNK' --name feat-nt 2>&1; true"
check "merge lock released after trunk error" test ! -d "$STORE/.orchestration/merge.lock"
$RC workspace remove --store teststore --project "$NOTRUNK" --name feat-nt
check "merge lock released" test ! -d "$STORE/.orchestration/merge.lock"
$RC workspace remove --store teststore --project "$PROJECT" --name feat-a

# a project that is not a repo yet gets initialized before the workspace is cut:
# empty folder -> git init on main + empty initial commit
EMPTY="$TMP/empty-project"
mkdir -p "$EMPTY"
check "workspace create on an empty folder succeeds" $RC workspace create --store teststore --project "$EMPTY" --name feat-empty
check "empty folder became a repo on main" test "$(git -C "$EMPTY" symbolic-ref --short HEAD)" = main
check "empty folder has an initial commit" git -C "$EMPTY" rev-parse --verify -q HEAD
check "change branch exists in the new repo" git -C "$EMPTY" rev-parse --verify -q refs/heads/change/feat-empty
$RC workspace remove --store teststore --project "$EMPTY" --name feat-empty
# ... and un-tracked files (a first idea already written) land in that initial commit
IDEA="$TMP/idea-project"
mkdir -p "$IDEA" && echo idea > "$IDEA/notes.md"
$RC workspace create --store teststore --project "$IDEA" --name feat-idea >/dev/null 2>&1
check "existing files are in the initial commit" git -C "$IDEA" cat-file -e HEAD:notes.md
check "worktree of the new repo carries those files" test -f "$STORE/.orchestration/workspaces/feat-idea/notes.md"
check "init is idempotent on a repo that already has a commit" test "$(git -C "$IDEA" rev-list --count main)" = 1
$RC workspace remove --store teststore --project "$IDEA" --name feat-idea

# trunk preflight: gate_full against a detached worktree of trunk_ref,
# cleaned up whether green or red, never touching any change's state
before_tree="$(grep '^gate_tree:' "$STORE/.orchestration/state/feat-a.yaml")"
check_out "gate run --trunk green runs gate_full in a trunk-preflight worktree" "FULL-OK in $STORE/.orchestration/workspaces/trunk-preflight." $RC gate run --store teststore --project "$PROJECT" --mode full --trunk
check "gate run --trunk green leaves no trunk-preflight worktree behind" bash -c "! git -C '$PROJECT' worktree list | grep -q trunk-preflight"
check "gate run --trunk green leaves a change's gate_tree unchanged" test "$(grep '^gate_tree:' "$STORE/.orchestration/state/feat-a.yaml")" = "$before_tree"

# red trunk: a second store whose gate_full fails
mkdir -p "$TMP/store2/openspec"
cat >> "$OPENSPEC_STORE_REGISTRY" <<EOF
  teststore2:
    local_path: $TMP/store2
EOF
cat > "$TMP/store2/openspec/config.yaml" <<'EOF'
orchestration:
  concurrency: 1
  gate_quick: "echo QUICK-OK in $PWD"
  gate_full: "exit 1"
EOF
check_out "gate run --trunk red names the trunk as red" "is red" bash -c "$RC gate run --store teststore2 --project '$PROJECT' --mode full --trunk 2>&1; true"
check "gate run --trunk red exits non-zero" bash -c "! $RC gate run --store teststore2 --project '$PROJECT' --mode full --trunk >/dev/null 2>&1"
check "gate run --trunk red leaves no trunk-preflight worktree behind" bash -c "! git -C '$PROJECT' worktree list | grep -q trunk-preflight"

# gate_timeout: a gate blocked on stdin, with a spawned child, is killed as a group
mkdir -p "$TMP/store3/openspec"
cat >> "$OPENSPEC_STORE_REGISTRY" <<EOF
  teststore3:
    local_path: $TMP/store3
EOF
cat > "$TMP/store3/openspec/config.yaml" <<'EOF'
orchestration:
  concurrency: 1
  gate_timeout: 2
  gate_full: "sleep 31337 & cat; wait"
EOF
t0=$SECONDS
check_out "gate run names a timed-out gate" "gate timed out after 2s" bash -c "$RC gate run --store teststore3 --project '$PROJECT' --mode full --trunk 2>&1; true"
check "gate run timeout returns within the limit, not when stdin closes" test $((SECONDS - t0)) -lt 15
check "gate run timeout exits 124" bash -c "$RC gate run --store teststore3 --project '$PROJECT' --mode full --trunk >/dev/null 2>&1; test \$? -eq 124"
check "gate run timeout kills the gate's children" bash -c "! pgrep -f 'sleep 31337'"

# tasks open: unchecked tasks.md lines, recorded as manual_tasks_open
$RC state init --store teststore --name feat-tasks
mkdir -p "$STORE/openspec/changes/feat-tasks"
cat > "$STORE/openspec/changes/feat-tasks/tasks.md" <<'EOF'
# Tasks
- [ ] 1.1 do thing
- [x] 1.2 done thing
- [ ] 1.3 another thing
EOF
check_out "tasks open prints the first unchecked line" "1.1 do thing" $RC tasks open --store teststore --name feat-tasks
check_out "tasks open prints the second unchecked line" "1.3 another thing" $RC tasks open --store teststore --name feat-tasks
$RC tasks open --store teststore --name feat-tasks >/dev/null
check_out "tasks open records the count" "manual_tasks_open: 2" $RC state get --store teststore --name feat-tasks

# `- [ ]` appearing mid-line (a checked task's own prose, or an unrelated
# bullet quoting the marker) must not be counted as an open task
$RC state init --store teststore --name feat-tasks-prose
mkdir -p "$STORE/openspec/changes/feat-tasks-prose"
cat > "$STORE/openspec/changes/feat-tasks-prose/tasks.md" <<'EOF'
# Tasks
- [x] 1.1 fix the `- [ ]` matching so checked lines aren't counted
- [ ] 1.2 add a tasks.md with two `- [ ]` lines for the test
EOF
out="$($RC tasks open --store teststore --name feat-tasks-prose)"
case "$out" in
  *"1.1"*) echo "FAIL tasks open counted a checked line containing '- [ ]' mid-line (got: $out)"; fails=$((fails+1)) ;;
  *) echo "ok   tasks open does not count a checked line containing '- [ ]' mid-line" ;;
esac
$RC tasks open --store teststore --name feat-tasks-prose >/dev/null
check_out "tasks open records 1 when only one real task line is unchecked" "manual_tasks_open: 1" $RC state get --store teststore --name feat-tasks-prose

mkdir -p "$STORE/openspec/changes/feat-allchecked"
cat > "$STORE/openspec/changes/feat-allchecked/tasks.md" <<'EOF'
- [x] 1.1 done
- [x] 1.2 done too
EOF
$RC state init --store teststore --name feat-allchecked
$RC tasks open --store teststore --name feat-allchecked >/dev/null
check_out "tasks open with every task checked records 0" "manual_tasks_open: 0" $RC state get --store teststore --name feat-allchecked

# a worktree copy of tasks.md wins over the store's own copy; done against
# "localstore" (local_path IS the project — SKILL.md Step 1), since in
# external mode (teststore) a project with its own openspec/ folder is
# refused outright by guard_project_openspec
mkdir -p "$PROJECT/openspec/changes/feat-wtask"
cat > "$PROJECT/openspec/changes/feat-wtask/tasks.md" <<'EOF'
- [ ] 9.1 store task
EOF
git -C "$PROJECT" add -A && git -C "$PROJECT" commit -qm "add feat-wtask tasks"
$RC workspace create --store localstore --project "$PROJECT" --name feat-wtask >/dev/null 2>&1
wtdir="$PROJECT/.orchestration/workspaces/feat-wtask"
cat > "$wtdir/openspec/changes/feat-wtask/tasks.md" <<'EOF'
- [ ] 2.1 worktree task
EOF
check_out "tasks open prefers the change's worktree copy over the store's" "worktree task" $RC tasks open --store localstore --name feat-wtask
check_out "tasks open records the worktree copy's count, not the store's" "manual_tasks_open: 1" $RC state get --store localstore --name feat-wtask
$RC workspace remove --store localstore --project "$PROJECT" --name feat-wtask
git -C "$PROJECT" rm -rq openspec/changes/feat-wtask >/dev/null 2>&1
git -C "$PROJECT" commit -qm "remove feat-wtask tasks" >/dev/null 2>&1
rmdir "$PROJECT/openspec" 2>/dev/null || rm -rf "$PROJECT/openspec"

# no change directory anywhere -> error, manual_tasks_open left untouched
$RC state init --store teststore --name feat-notasks
check_out "tasks open errors when no change directory exists anywhere" "no change directory found" bash -c "$RC tasks open --store teststore --name feat-notasks 2>&1; true"
check_out "tasks open writes nothing when no change directory exists" 'manual_tasks_open: ""' $RC state get --store teststore --name feat-notasks

# change directory exists but has no tasks.md (e.g. a triage bugfix)
mkdir -p "$STORE/openspec/changes/feat-notasksmd"
$RC state init --store teststore --name feat-notasksmd
check_out "tasks open without tasks.md reports it" "no tasks.md for feat-notasksmd" $RC tasks open --store teststore --name feat-notasksmd
check_out "tasks open without tasks.md records 0" "manual_tasks_open: 0" $RC state get --store teststore --name feat-notasksmd

# =====================================================================
# parallel-units: split recorded in state, units_check
# =====================================================================
$RC state init --store teststore --name feat-units
check_out "state init has empty units fields" 'units: ""' $RC state get --store teststore --name feat-units
check_out "state init has empty unit_deps" 'unit_deps: ""' $RC state get --store teststore --name feat-units
check_out "state init has empty unit_tasks" 'unit_tasks: ""' $RC state get --store teststore --name feat-units
check_out "state init has empty ui_units" 'ui_units: ""' $RC state get --store teststore --name feat-units
check_out "state init has empty parallel" 'parallel: ""' $RC state get --store teststore --name feat-units

$RC state set --store teststore --name feat-units seams "s=a.js,b.js"
$RC state set --store teststore --name feat-units units "a=a.js;b=b.js" unit_deps "a=b;b=a"
cycle_out="$($RC units check --store teststore --name feat-units 2>&1; true)"
case "$cycle_out" in *a*) echo "ok   units check: cycle names node a" ;; *) echo "FAIL units check: cycle names node a (got: $cycle_out)"; fails=$((fails+1)) ;; esac
case "$cycle_out" in *b*) echo "ok   units check: cycle names node b" ;; *) echo "FAIL units check: cycle names node b (got: $cycle_out)"; fails=$((fails+1)) ;; esac
check "units check: cycle exits non-zero" bash -c "! $RC units check --store teststore --name feat-units >/dev/null 2>&1"

$RC state set --store teststore --name feat-units units "a=x.js;b=x.js" unit_deps ""
$RC state set --store teststore --name feat-units seams "s=x.js"
check_out "units check: unordered overlap rejected" "no dep path" bash -c "$RC units check --store teststore --name feat-units 2>&1; true"
$RC state set --store teststore --name feat-units unit_deps "b=a"
check "units check: overlap ok once ordered by a dep" $RC units check --store teststore --name feat-units

$RC state set --store teststore --name feat-units units "a=x.js,y.js" unit_deps "" seams "s=x.js"
check_out "units check: file outside seams named" "y.js" bash -c "$RC units check --store teststore --name feat-units 2>&1; true"

$RC state set --store teststore --name feat-units units "A_b=x.js" seams "s=x.js"
check_out "units check: bad kebab-case name rejected" "bad unit name" bash -c "$RC units check --store teststore --name feat-units 2>&1; true"

$RC state set --store teststore --name feat-units units "a=x.js;b=y.js" unit_deps "" seams "s=x.js,y.js" unit_tasks "a=1.1;b=1.1"
check_out "units check: task id in two units rejected" "task '1.1'" bash -c "$RC units check --store teststore --name feat-units 2>&1; true"

mkdir -p "$STORE/openspec/changes/feat-units"
cat > "$STORE/openspec/changes/feat-units/tasks.md" <<'EOF'
# Tasks
- [ ] 1.1 do thing
- [ ] 1.2 another thing
EOF
$RC state set --store teststore --name feat-units units "a=x.js" unit_deps "" seams "s=x.js,y.js" unit_tasks "a=1.1"
check_out "units check CLI: unassigned task printed" "unassigned: 1.2" $RC units check --store teststore --name feat-units
check "units check CLI exits 0 when the check passes" $RC units check --store teststore --name feat-units
check "next succeeds on a valid split with no tasks.md anywhere" bash -c "rm -rf '$STORE/openspec/changes/feat-units'; $RC next --store teststore --name feat-units"

check_out "units single --ui builds one unit from the seam union" "units: all=a.js,b.js" bash -c "
  $RC state set --store teststore --name feat-units seams 's1=a.js;s2=b.js' units '' unit_tasks '' ui_units ''
  $RC units single --store teststore --name feat-units --ui
  $RC state get --store teststore --name feat-units
"
check_out "units single --ui sets ui_units to all" "ui_units: all" $RC state get --store teststore --name feat-units

# =====================================================================
# scheduler: units next (ready/running/capacity/dep gating/concurrency)
# =====================================================================
$RC state init --store teststore --name feat-sched
$RC state set --store teststore --name feat-sched seams "s=a.js,b.js,c.js" units "c=c.js;a=a.js;b=b.js" unit_deps ""
check_out "units next: ready in units field order, capacity 2" "ready: c a" $RC units next --store teststore --name feat-sched
udirS="$STORE/.orchestration/state/feat-sched.units"
mkdir -p "$udirS"
cat > "$udirS/c.yaml" <<'EOF'
status: running
iterations: 0
EOF
check_out "units next: running unit consumes capacity" "ready: a" $RC units next --store teststore --name feat-sched
check_out "units next: running unit listed" "running: c" $RC units next --store teststore --name feat-sched
cat > "$udirS/a.yaml" <<'EOF'
status: reviewing
iterations: 1
EOF
cat > "$udirS/b.yaml" <<'EOF'
status: running
iterations: 0
EOF
check_line "units next: review+running hold both slots -> empty ready" "ready: " $RC units next --store teststore --name feat-sched
check_out "units next: capacity exhausted" "capacity: 0" $RC units next --store teststore --name feat-sched
cat > "$udirS/a.yaml" <<'EOF'
status: resolving
iterations: 1
EOF
check_out "units next: resolving also holds a slot" "capacity: 0" $RC units next --store teststore --name feat-sched

$RC state init --store teststore --name feat-dep
$RC state set --store teststore --name feat-dep seams "s=a.js,b.js" units "a=a.js;b=b.js" unit_deps "b=a"
check_line "units next: dep gating — dependent not ready" "ready: a" $RC units next --store teststore --name feat-dep
udirD="$STORE/.orchestration/state/feat-dep.units"
mkdir -p "$udirD"
cat > "$udirD/a.yaml" <<'EOF'
status: reviewed
iterations: 1
EOF
check_line "units next: dep reviewed but not merged -> still not ready" "ready: " $RC units next --store teststore --name feat-dep
cat > "$udirD/a.yaml" <<'EOF'
status: merged
iterations: 1
EOF
check_out "units next: dep merged -> dependent ready" "ready: b" $RC units next --store teststore --name feat-dep

mkdir -p "$TMP/store3/openspec"
cat >> "$OPENSPEC_STORE_REGISTRY" <<EOF
  teststore3:
    local_path: $TMP/store3
EOF
cat > "$TMP/store3/openspec/config.yaml" <<'EOF'
orchestration:
  concurrency: 1
  unit_concurrency: 3
  gate_quick: "echo QUICK-OK in $PWD"
  gate_full: "echo FULL-OK in $PWD"
EOF
$RC state init --store teststore3 --name feat-cap3
$RC state set --store teststore3 --name feat-cap3 seams "s=a.js,b.js,c.js" units "a=a.js;b=b.js;c=c.js" unit_deps ""
check_out "unit_concurrency overrides concurrency" "ready: a b c" $RC units next --store teststore3 --name feat-cap3

# unit_concurrency listed BEFORE concurrency must not leak into the
# change-level slot cap (V3: both awk matches must be anchored to the key)
mkdir -p "$TMP/store4/openspec"
cat >> "$OPENSPEC_STORE_REGISTRY" <<EOF
  teststore4:
    local_path: $TMP/store4
EOF
cat > "$TMP/store4/openspec/config.yaml" <<'EOF'
orchestration:
  unit_concurrency: 5
  concurrency: 1
  gate_quick: "echo QUICK-OK in $PWD"
  gate_full: "echo FULL-OK in $PWD"
EOF
git clone -q "$TMP/origin" "$TMP/project4"
s4="$($RC slot acquire --store teststore4 --project "$TMP/project4")"
check_out "unit_concurrency listed first does not raise the change-level cap" "no free slot (cap=1)" bash -c "$RC slot acquire --store teststore4 --project '$TMP/project4' 2>&1; true"
$RC slot release --store teststore4 --slot "$s4"
$RC state init --store teststore4 --name feat-cap4
$RC state set --store teststore4 --name feat-cap4 seams "s=a.js,b.js,c.js" units "a=a.js;b=b.js;c=c.js" unit_deps ""
check_out "unit_concurrency still read correctly when listed first" "ready: a b c" $RC units next --store teststore4 --name feat-cap4

# defaults with neither key set: 2 changes per project, 3 units per change
mkdir -p "$TMP/store-def/openspec"
cat >> "$OPENSPEC_STORE_REGISTRY" <<EOF
  store-def:
    local_path: $TMP/store-def
EOF
cat > "$TMP/store-def/openspec/config.yaml" <<'EOF'
orchestration:
  gate_quick: "echo QUICK-OK in $PWD"
  gate_full: "echo FULL-OK in $PWD"
EOF
git clone -q "$TMP/origin" "$TMP/project-def"
$RC state init --store store-def --name feat-def
$RC state set --store store-def --name feat-def seams "s=a.js,b.js,c.js,d.js" units "a=a.js;b=b.js;c=c.js;d=d.js" unit_deps ""
check_out "unit_concurrency defaults to 3" "ready: a b c" $RC units next --store store-def --name feat-def
check_out "unit_concurrency default reports capacity 3" "capacity: 3" $RC units next --store store-def --name feat-def
sd1="$($RC slot acquire --store store-def --project "$TMP/project-def")"
sd2="$($RC slot acquire --store store-def --project "$TMP/project-def")"
check "concurrency defaults to 2: two slots acquired" test -n "$sd1" -a -n "$sd2"
check_out "concurrency default refuses a third slot" "no free slot (cap=2)" bash -c "$RC slot acquire --store store-def --project '$TMP/project-def' 2>&1; true"

# units list: prints "<u> <status> <iterations>", pending when no unit file
check_line "units list: created unit shows its status and iterations" "c running 0" $RC units list --store teststore --name feat-sched
check_line "units list: unit with no file shows pending 0" "b pending 0" $RC units list --store teststore3 --name feat-cap3

# =====================================================================
# units merge-order
# =====================================================================
$RC state init --store teststore --name feat-order
$RC state set --store teststore --name feat-order seams "s=a.js,b.js,c.js" units "c=c.js;b=b.js;a=a.js" unit_deps "c=a;b=a"
check_out "units merge-order: deps before dependents, ties by field order" "a c b" $RC units merge-order --store teststore --name feat-order
$RC state set --store teststore --name feat-order unit_deps "a=b;b=a"
check_out "units merge-order: cycle errors" "cycle" bash -c "$RC units merge-order --store teststore --name feat-order 2>&1; true"

# =====================================================================
# per-unit worktree + branch lifecycle
# =====================================================================
UPROJECT="$TMP/uproject"
git init -q -b main "$UPROJECT"
echo one > "$UPROJECT/x.js"; echo two > "$UPROJECT/y.js"
git -C "$UPROJECT" add -A && git -C "$UPROJECT" commit -qm init

$RC state init --store teststore --name feat-uw
$RC state set --store teststore --name feat-uw seams "s=x.js,y.js,z.js" units "a=x.js;b=y.js;c=z.js" unit_deps "b=a"
$RC workspace create --store teststore --project "$UPROJECT" --name feat-uw >/dev/null 2>&1

check_out "unit create: dep not merged refused" "not merged" bash -c "$RC unit create --store teststore --project '$UPROJECT' --name feat-uw --unit b 2>&1; true"
check "unit create: dep not merged creates no branch" bash -c "! git -C '$UPROJECT' rev-parse --verify -q change/feat-uw.b"

uwt="$($RC unit create --store teststore --project "$UPROJECT" --name feat-uw --unit a)"
check "unit create: worktree exists at the expected path" test "$uwt" = "$STORE/.orchestration/workspaces/feat-uw.a"
check "unit create: branch exists" git -C "$UPROJECT" rev-parse --verify -q change/feat-uw.a
check_out "unit create: unit file has status running" "status: running" $RC unit get --store teststore --name feat-uw --unit a
basesha="$(git -C "$UPROJECT" rev-parse change/feat-uw)"
check_out "unit create: base equals change branch tip" "base: $basesha" $RC unit get --store teststore --name feat-uw --unit a

echo dirty > "$STORE/.orchestration/workspaces/feat-uw/dirty.txt"
check_out "unit create: dirty change worktree refused" "uncommitted" bash -c "$RC unit create --store teststore --project '$UPROJECT' --name feat-uw --unit c 2>&1; true"
rm -f "$STORE/.orchestration/workspaces/feat-uw/dirty.txt"
check "unit create: dirty-worktree refusal created no branch" bash -c "! git -C '$UPROJECT' rev-parse --verify -q change/feat-uw.c"

check_out "unit create: second create on a running unit refused" "already exists" bash -c "$RC unit create --store teststore --project '$UPROJECT' --name feat-uw --unit a 2>&1; true"

$RC unit remove --store teststore --project "$UPROJECT" --name feat-uw --unit a
check "unit remove: worktree gone" test ! -e "$uwt"
check "unit remove: branch gone" bash -c "! git -C '$UPROJECT' rev-parse --verify -q change/feat-uw.a"
# unit remove leaves the unit's status file alone (status unchanged) — drop
# it here to simulate a never-created unit for the next (workspace remove) check
rm -f "$STORE/.orchestration/state/feat-uw.units/a.yaml"

uwt2="$($RC unit create --store teststore --project "$UPROJECT" --name feat-uw --unit a)"
$RC workspace remove --store teststore --project "$UPROJECT" --name feat-uw
check "workspace remove: no change/<name>.* branch remains" bash -c "[ -z \"\$(git -C '$UPROJECT' branch --list 'change/feat-uw.*')\" ]"
check "workspace remove: unit worktree gone too" test ! -e "$uwt2"
rm -f "$STORE/.orchestration/state/feat-uw.units/a.yaml"

# V6: a unit whose worktree dir is already gone (interrupted unit remove, a
# manual prune) must still lose its branch via workspace remove — derived
# from the units field through workspace_path, not from scanning dirs.
$RC workspace create --store teststore --project "$UPROJECT" --name feat-uw >/dev/null 2>&1
uwt3="$($RC unit create --store teststore --project "$UPROJECT" --name feat-uw --unit a)"
git -C "$UPROJECT" worktree remove "$uwt3" --force
check "V6 setup: unit a worktree dir is gone" test ! -e "$uwt3"
check "V6 setup: unit a branch still exists" git -C "$UPROJECT" rev-parse --verify -q change/feat-uw.a
$RC workspace remove --store teststore --project "$UPROJECT" --name feat-uw
check "workspace remove: unit branch gone even though its worktree dir was already gone" bash -c "! git -C '$UPROJECT' rev-parse --verify -q change/feat-uw.a"
rm -f "$STORE/.orchestration/state/feat-uw.units/a.yaml"

# gate run --unit: runs in the unit worktree, never writes gate_tree
$RC workspace create --store teststore --project "$UPROJECT" --name feat-uw >/dev/null 2>&1
uwt="$($RC unit create --store teststore --project "$UPROJECT" --name feat-uw --unit a)"
check_out "gate run --unit runs in the unit worktree" "$uwt" $RC gate run --store teststore --project "$UPROJECT" --name feat-uw --unit a --mode full
check_out "gate run --unit leaves gate_tree alone" 'gate_tree: ""' $RC state get --store teststore --name feat-uw

# unit checks-done / unit iterate gating
lines_before="$($RC session list --store teststore --name feat-uw 2>&1 | wc -l)"
check_out "unit iterate before checks-done is refused" "checks-done" bash -c "$RC unit iterate --store teststore --project '$UPROJECT' --name feat-uw --unit a 2>&1; true"
lines_after="$($RC session list --store teststore --name feat-uw 2>&1 | wc -l)"
check "a refused iterate logs nothing" test "$lines_before" -eq "$lines_after"
check_out "checks-done at base is refused" "still equals its base" bash -c "$RC unit checks-done --store teststore --project '$UPROJECT' --name feat-uw --unit a 2>&1; true"
echo check > "$uwt/a.check.js"
git -C "$uwt" add -A && git -C "$uwt" commit -qm "add checks for unit a"
$RC unit checks-done --store teststore --project "$UPROJECT" --name feat-uw --unit a
headsha="$(git -C "$uwt" rev-parse HEAD)"
check_out "checks-done records HEAD as checks_commit" "checks_commit: $headsha" $RC unit get --store teststore --name feat-uw --unit a

# =====================================================================
# unit iterate: engine-run checks, capped, session-logged
# =====================================================================
mkdir -p "$TMP/storeu1/openspec"
cat >> "$OPENSPEC_STORE_REGISTRY" <<EOF
  storeu1:
    local_path: $TMP/storeu1
EOF
cat > "$TMP/storeu1/openspec/config.yaml" <<'EOF'
orchestration:
  concurrency: 2
  unit_concurrency: 2
  gate_quick: 'test -f OK && { [ -z "$UNIT_SCREENSHOT" ] || touch "$UNIT_SCREENSHOT"; }'
  gate_full: "echo FULL-OK in $PWD"
EOF
UPROJECT1="$TMP/uproject1"
git init -q -b main "$UPROJECT1"
echo one > "$UPROJECT1/a.js"
git -C "$UPROJECT1" add -A && git -C "$UPROJECT1" commit -qm init

$RC state init --store storeu1 --name feat-iter
$RC state set --store storeu1 --name feat-iter seams "s=a.js" units "a=a.js" unit_deps "" ui_units "a"
$RC workspace create --store storeu1 --project "$UPROJECT1" --name feat-iter >/dev/null 2>&1
iwt="$($RC unit create --store storeu1 --project "$UPROJECT1" --name feat-iter --unit a)"
echo check > "$iwt/a.test.js"; git -C "$iwt" add -A && git -C "$iwt" commit -qm checks
$RC unit checks-done --store storeu1 --project "$UPROJECT1" --name feat-iter --unit a

for i in 1 2 3 4; do
  check "unit iterate #$i returns red (no OK file yet)" bash -c "! $RC unit iterate --store storeu1 --project '$UPROJECT1' --name feat-iter --unit a >/dev/null 2>&1"
done
n_red="$($RC session list --store storeu1 --name feat-iter | grep -c 'checks=red')"
check "exactly 4 red iterate entries logged" test "$n_red" = 4
touch "$iwt/OK"
check "5th iterate returns green" $RC unit iterate --store storeu1 --project "$UPROJECT1" --name feat-iter --unit a
check_out "unit status is green" "status: green" $RC unit get --store storeu1 --name feat-iter --unit a
check_out "screenshot recorded as the absolute iteration-5 path" "$TMP/storeu1/.orchestration/state/feat-iter.units/a/screenshot-5.png" $RC unit get --store storeu1 --name feat-iter --unit a
check "recorded screenshot file exists" test -f "$TMP/storeu1/.orchestration/state/feat-iter.units/a/screenshot-5.png"
n_green="$($RC session list --store storeu1 --name feat-iter | grep -c 'checks=green')"
check "exactly 1 green iterate entry logged" test "$n_green" = 1
iters_log="$($RC session list --store storeu1 --name feat-iter | grep -o 'iteration=[0-9]*' | sort -u | tr '\n' ' ')"
check "iterations 1..5 all logged, once each" test "$iters_log" = "iteration=1 iteration=2 iteration=3 iteration=4 iteration=5 "
check_out "iterate entries carry tier standard" "tier=standard" $RC session list --store storeu1 --name feat-iter
check_out "unit create records the leaf's tier" "tier: standard" $RC unit get --store storeu1 --name feat-iter --unit a
nlines_before="$($RC session list --store storeu1 --name feat-iter | wc -l | tr -d ' ')"
check "6th iterate is refused" bash -c "! $RC unit iterate --store storeu1 --project '$UPROJECT1' --name feat-iter --unit a >/dev/null 2>&1"
check_out "6th iterate names the iteration cap" "iteration cap" bash -c "$RC unit iterate --store storeu1 --project '$UPROJECT1' --name feat-iter --unit a 2>&1; true"
nlines_after="$($RC session list --store storeu1 --name feat-iter | wc -l | tr -d ' ')"
check "6th iterate appends no log entry" test "$nlines_before" = "$nlines_after"
check_out "unit status is failed past the cap" "status: failed" $RC unit get --store storeu1 --name feat-iter --unit a

# gate_ui: runs after gate_quick for UI units only
mkdir -p "$TMP/storeui/openspec"
cat >> "$OPENSPEC_STORE_REGISTRY" <<EOF
  storeui:
    local_path: $TMP/storeui
EOF
cat > "$TMP/storeui/openspec/config.yaml" <<'EOF'
orchestration:
  unit_concurrency: 2
  gate_quick: 'test -f OK'
  gate_ui: 'echo UI-RAN >> "$UNIT_SCREENSHOT.log" && touch "$UNIT_SCREENSHOT"'
  gate_full: "echo FULL-OK"
EOF
UPROJECTUI="$TMP/uprojectui"
git init -q -b main "$UPROJECTUI"
echo one > "$UPROJECTUI/a.js"; echo two > "$UPROJECTUI/b.js"
git -C "$UPROJECTUI" add -A && git -C "$UPROJECTUI" commit -qm init
$RC state init --store storeui --name feat-ui
$RC state set --store storeui --name feat-ui seams "s=a.js,b.js" units "a=a.js;b=b.js" unit_deps "" ui_units "a"
$RC workspace create --store storeui --project "$UPROJECTUI" --name feat-ui >/dev/null 2>&1
uwa="$($RC unit create --store storeui --project "$UPROJECTUI" --name feat-ui --unit a)"
uwb="$($RC unit create --store storeui --project "$UPROJECTUI" --name feat-ui --unit b)"
for w in "$uwa" "$uwb"; do echo check > "$w/t.js"; git -C "$w" add -A && git -C "$w" commit -qm checks; touch "$w/OK"; done
$RC unit checks-done --store storeui --project "$UPROJECTUI" --name feat-ui --unit a
$RC unit checks-done --store storeui --project "$UPROJECTUI" --name feat-ui --unit b
check "UI unit: gate_quick then gate_ui -> green" $RC unit iterate --store storeui --project "$UPROJECTUI" --name feat-ui --unit a
check "UI unit: gate_ui ran" test -f "$TMP/storeui/.orchestration/state/feat-ui.units/a/screenshot-1.png.log"
check "non-UI unit: green from gate_quick alone" $RC unit iterate --store storeui --project "$UPROJECTUI" --name feat-ui --unit b
check "non-UI unit: gate_ui did not run" bash -c "! ls '$TMP/storeui/.orchestration/state/feat-ui.units/b/' | grep -q log"
rm -f "$uwa/OK"
check "UI unit: red gate_quick is red even when gate_ui would pass" bash -c "! $RC unit iterate --store storeui --project '$UPROJECTUI' --name feat-ui --unit a >/dev/null 2>&1"

# a non-UI unit red every time ends failed at the cap too
UPROJECT1B="$TMP/uproject1b"
git init -q -b main "$UPROJECT1B"
echo one > "$UPROJECT1B/b.js"
git -C "$UPROJECT1B" add -A && git -C "$UPROJECT1B" commit -qm init
$RC state init --store storeu1 --name feat-iter-red
$RC state set --store storeu1 --name feat-iter-red seams "s=b.js" units "b=b.js" unit_deps ""
$RC workspace create --store storeu1 --project "$UPROJECT1B" --name feat-iter-red >/dev/null 2>&1
rwt="$($RC unit create --store storeu1 --project "$UPROJECT1B" --name feat-iter-red --unit b)"
echo check > "$rwt/b.test.js"; git -C "$rwt" add -A && git -C "$rwt" commit -qm checks
$RC unit checks-done --store storeu1 --project "$UPROJECT1B" --name feat-iter-red --unit b
for i in 1 2 3 4 5; do
  $RC unit iterate --store storeu1 --project "$UPROJECT1B" --name feat-iter-red --unit b >/dev/null 2>&1 || true
done
check_out "non-UI unit red at the cap -> failed" "status: failed" $RC unit get --store storeu1 --name feat-iter-red --unit b

# unit-revise round trip (V2): blocking critique -> orchestrator clears it
# (status running, critique "") -> iterate green again -> unit-critique
UPROJECT1C="$TMP/uproject1c"
git init -q -b main "$UPROJECT1C"
echo one > "$UPROJECT1C/c.js"
git -C "$UPROJECT1C" add -A && git -C "$UPROJECT1C" commit -qm init
$RC state init --store storeu1 --name feat-revise-flow
$RC state set --store storeu1 --name feat-revise-flow phase applying seams "s=c.js" units "c=c.js" unit_deps ""
$RC workspace create --store storeu1 --project "$UPROJECT1C" --name feat-revise-flow >/dev/null 2>&1
cwt1="$($RC unit create --store storeu1 --project "$UPROJECT1C" --name feat-revise-flow --unit c)"
echo check > "$cwt1/c.test.js"; git -C "$cwt1" add -A && git -C "$cwt1" commit -qm checks
$RC unit checks-done --store storeu1 --project "$UPROJECT1C" --name feat-revise-flow --unit c
touch "$cwt1/OK"
check "unit-revise flow: first iterate is green" $RC unit iterate --store storeu1 --project "$UPROJECT1C" --name feat-revise-flow --unit c
$RC unit set --store storeu1 --name feat-revise-flow --unit c status reviewing critique "blocking:1"
check_out "unit-revise flow: blocking critique under the cap -> unit-revise" "action: unit-revise" $RC next --store storeu1 --name feat-revise-flow
$RC unit set --store storeu1 --name feat-revise-flow --unit c status running critique ""
check_out "unit-revise flow: after clearing, status is running critique empty" "status: running" $RC unit get --store storeu1 --name feat-revise-flow --unit c
check_line "unit-revise flow: critique field cleared" "critique: " $RC unit get --store storeu1 --name feat-revise-flow --unit c
check "unit-revise flow: re-dispatched iterate goes green" $RC unit iterate --store storeu1 --project "$UPROJECT1C" --name feat-revise-flow --unit c
check_out "unit-revise flow: green with critique cleared -> unit-critique" "action: unit-critique" $RC next --store storeu1 --name feat-revise-flow

# UI green needs the screenshot: a gate_quick that exits 0 but never writes it
mkdir -p "$TMP/storeu2/openspec"
cat >> "$OPENSPEC_STORE_REGISTRY" <<EOF
  storeu2:
    local_path: $TMP/storeu2
EOF
cat > "$TMP/storeu2/openspec/config.yaml" <<'EOF'
orchestration:
  concurrency: 1
  gate_quick: "exit 0"
  gate_full: "exit 0"
EOF
UPROJECT2="$TMP/uproject2"
git init -q -b main "$UPROJECT2"
echo one > "$UPROJECT2/a.js"
git -C "$UPROJECT2" add -A && git -C "$UPROJECT2" commit -qm init
$RC state init --store storeu2 --name feat-nopng
$RC state set --store storeu2 --name feat-nopng seams "s=a.js" units "a=a.js" unit_deps "" ui_units "a"
$RC workspace create --store storeu2 --project "$UPROJECT2" --name feat-nopng >/dev/null 2>&1
nwt="$($RC unit create --store storeu2 --project "$UPROJECT2" --name feat-nopng --unit a)"
echo check > "$nwt/a.test.js"; git -C "$nwt" add -A && git -C "$nwt" commit -qm checks
$RC unit checks-done --store storeu2 --project "$UPROJECT2" --name feat-nopng --unit a
check "UI unit with a gate_quick that writes no PNG returns red" bash -c "! $RC unit iterate --store storeu2 --project '$UPROJECT2' --name feat-nopng --unit a >/dev/null 2>&1"
check_out "that iterate is logged red" "checks=red" $RC session list --store storeu2 --name feat-nopng
check "its status is not green" bash -c "! grep -q '^status: green' <($RC unit get --store storeu2 --name feat-nopng --unit a)"

# only the owning unit's test writes the screenshot
mkdir -p "$TMP/storeu3/openspec"
cat >> "$OPENSPEC_STORE_REGISTRY" <<EOF
  storeu3:
    local_path: $TMP/storeu3
EOF
cat > "$TMP/storeu3/openspec/config.yaml" <<'EOF'
orchestration:
  concurrency: 2
  unit_concurrency: 2
  gate_quick: '[ "$UNIT_NAME" != a ] || touch "$UNIT_SCREENSHOT"'
  gate_full: "exit 0"
EOF
UPROJECT3="$TMP/uproject3"
git init -q -b main "$UPROJECT3"
echo one > "$UPROJECT3/a.js"; echo two > "$UPROJECT3/b.js"
git -C "$UPROJECT3" add -A && git -C "$UPROJECT3" commit -qm init
$RC state init --store storeu3 --name feat-owner
$RC state set --store storeu3 --name feat-owner seams "s=a.js,b.js" units "a=a.js;b=b.js" unit_deps "" ui_units "a,b"
$RC workspace create --store storeu3 --project "$UPROJECT3" --name feat-owner >/dev/null 2>&1
owt_a="$($RC unit create --store storeu3 --project "$UPROJECT3" --name feat-owner --unit a)"
owt_b="$($RC unit create --store storeu3 --project "$UPROJECT3" --name feat-owner --unit b)"
echo c > "$owt_a/a.test.js"; git -C "$owt_a" add -A && git -C "$owt_a" commit -qm checks
echo c > "$owt_b/b.test.js"; git -C "$owt_b" add -A && git -C "$owt_b" commit -qm checks
$RC unit checks-done --store storeu3 --project "$UPROJECT3" --name feat-owner --unit a
$RC unit checks-done --store storeu3 --project "$UPROJECT3" --name feat-owner --unit b
check "owner store: non-owning unit b returns red" bash -c "! $RC unit iterate --store storeu3 --project '$UPROJECT3' --name feat-owner --unit b >/dev/null 2>&1"
check "owner store: unit b records no screenshot" bash -c "! grep -q '^screenshot: /' <($RC unit get --store storeu3 --name feat-owner --unit b)"
check "owner store: owning unit a returns green" $RC unit iterate --store storeu3 --project "$UPROJECT3" --name feat-owner --unit a
check_out "owner store: unit a status green" "status: green" $RC unit get --store storeu3 --name feat-owner --unit a

# =====================================================================
# critic over green units with screenshots
# =====================================================================
check_out "units ready-for-review lists the green unit" "unit: a" $RC units ready-for-review --store storeu3 --name feat-owner
out_rfr="$($RC units ready-for-review --store storeu3 --name feat-owner)"
case "$out_rfr" in
  *"unit: b"*) echo "FAIL units ready-for-review includes the non-green unit b"; fails=$((fails+1)) ;;
  *) echo "ok   units ready-for-review excludes the non-green unit b" ;;
esac
check_out "units ready-for-review prints the absolute screenshot path" "$TMP/storeu3/.orchestration/state/feat-owner.units/a/screenshot-1.png" $RC units ready-for-review --store storeu3 --name feat-owner

critique_dir="$TMP/storeu3/.orchestration/state/feat-owner.units"
shotpath="$critique_dir/a/screenshot-1.png"
echo "basename only: screenshot-1.png" > "$critique_dir/a.critique.md"
check_out "unit set critique: report with only the basename is refused" "does not contain" bash -c "$RC unit set --store storeu3 --name feat-owner --unit a critique clean 2>&1; true"
printf 'looks correct: %s\n' "$shotpath" > "$critique_dir/a.critique.md"
check "unit set critique: report with the absolute path is accepted" $RC unit set --store storeu3 --name feat-owner --unit a critique clean
check_out "unit critique recorded" "critique: clean" $RC unit get --store storeu3 --name feat-owner --unit a

$RC session append --store storeu3 --name feat-owner role worker phase proposed tier deep model claude-opus-5-custom transcript_id u1
# avoid piping a live process into `head`: with pipefail the writer's SIGPIPE
# (once head closes the pipe after one line) would kill this whole script
out1_full="$($RC model critic --store storeu3 --name feat-owner)"; out1="${out1_full%%$'\n'*}"
out2_full="$($RC model critic --store storeu3 --name feat-owner --unit a)"; out2="${out2_full%%$'\n'*}"
check "model critic line 1 is max over the deep proposer" test "$out1" = claude-fable-5-1
check "model critic --unit line 1 is deep over the standard leaf worker" test "$out2" = claude-opus-5
check_out "model critic --unit contract mentions checks_commit" "checks_commit" $RC model critic --store storeu3 --name feat-owner --unit a
check_out "model critic --unit contract mentions screenshot" "screenshot" $RC model critic --store storeu3 --name feat-owner --unit a
check_out "model critic --unit contract mentions input:" "input:" $RC model critic --store storeu3 --name feat-owner --unit a
check "model critic --unit contract names no Project glossary or ADRs" bash -c "out=\"\$($RC model critic --store storeu3 --name feat-owner --unit a)\" && case \"\$out\" in *openspec/CONTEXT.md*|*openspec/adr/*) exit 1 ;; esac"

# =====================================================================
# unit merge: dependency-ordered, scope-checked, conflict handling
# =====================================================================
MPROJECT="$TMP/mproject"
git init -q -b main "$MPROJECT"
echo one > "$MPROJECT/a.js"; echo two > "$MPROJECT/b.js"
git -C "$MPROJECT" add -A && git -C "$MPROJECT" commit -qm init

$RC state init --store teststore --name feat-merge
mkdir -p "$STORE/openspec/changes/feat-merge"
cat > "$STORE/openspec/changes/feat-merge/tasks.md" <<'EOF'
# Tasks
- [ ] 1.1 unit a task
EOF
$RC state set --store teststore --name feat-merge seams "s=a.js,b.js" units "a=a.js" unit_deps "" unit_tasks "a=1.1"
$RC workspace create --store teststore --project "$MPROJECT" --name feat-merge >/dev/null 2>&1
mwt="$($RC unit create --store teststore --project "$MPROJECT" --name feat-merge --unit a)"
echo changed > "$mwt/a.js"; git -C "$mwt" add -A && git -C "$mwt" commit -qm "implement a"
$RC unit set --store teststore --name feat-merge --unit a status reviewed
$RC unit merge --store teststore --project "$MPROJECT" --name feat-merge --unit a
check "merge: change branch has the unit's commit" bash -c "git -C '$MPROJECT' log change/feat-merge --oneline | grep -q 'implement a'"
check_out "merge: task ticked in tasks.md" "[x] 1.1 unit a task" cat "$STORE/openspec/changes/feat-merge/tasks.md"
check "merge: unit worktree removed" test ! -e "$mwt"
check "merge: unit branch removed" bash -c "! git -C '$MPROJECT' rev-parse --verify -q change/feat-merge.a"
check_out "merge: status merged" "status: merged" $RC unit get --store teststore --name feat-merge --unit a
check_out "merge: event=merge result=merged logged" "event=merge result=merged" $RC session list --store teststore --name feat-merge

# out-of-scope file refused, change branch unchanged
$RC state init --store teststore --name feat-scope
$RC state set --store teststore --name feat-scope seams "s=a.js,b.js" units "a=a.js" unit_deps ""
$RC workspace create --store teststore --project "$MPROJECT" --name feat-scope >/dev/null 2>&1
swt="$($RC unit create --store teststore --project "$MPROJECT" --name feat-scope --unit a)"
echo x > "$swt/b.js"; git -C "$swt" add -A && git -C "$swt" commit -qm "touches out-of-scope file"
$RC unit set --store teststore --name feat-scope --unit a status reviewed
before_tip="$(git -C "$MPROJECT" rev-parse change/feat-scope)"
check_out "merge: out-of-scope file named and refused" "b.js" bash -c "$RC unit merge --store teststore --project '$MPROJECT' --name feat-scope --unit a 2>&1; true"
check "merge: out-of-scope refusal leaves change branch unchanged" test "$before_tip" = "$(git -C "$MPROJECT" rev-parse change/feat-scope)"
$RC workspace remove --store teststore --project "$MPROJECT" --name feat-scope

# dep not merged refused (no real worktree needed: the dep check is state-only)
$RC state init --store teststore --name feat-mdep
$RC state set --store teststore --name feat-mdep seams "s=a.js,b.js" units "a=a.js;b=b.js" unit_deps "b=a"
$RC workspace create --store teststore --project "$MPROJECT" --name feat-mdep >/dev/null 2>&1
$RC unit create --store teststore --project "$MPROJECT" --name feat-mdep --unit a >/dev/null
$RC unit set --store teststore --name feat-mdep --unit a status reviewed
mkdir -p "$STORE/.orchestration/state/feat-mdep.units"
cat > "$STORE/.orchestration/state/feat-mdep.units/b.yaml" <<'EOF'
status: reviewed
EOF
check_out "merge: dep not merged refused" "not merged" bash -c "$RC unit merge --store teststore --project '$MPROJECT' --name feat-mdep --unit b 2>&1; true"
$RC workspace remove --store teststore --project "$MPROJECT" --name feat-mdep

# conflict -> conflict; a second conflict -> failed; one event=merge per attempt
$RC state init --store teststore --name feat-conflict
$RC state set --store teststore --name feat-conflict seams "s=a.js" units "a=a.js" unit_deps ""
$RC workspace create --store teststore --project "$MPROJECT" --name feat-conflict >/dev/null 2>&1
cwt="$($RC unit create --store teststore --project "$MPROJECT" --name feat-conflict --unit a)"
echo "unit-change" > "$cwt/a.js"; git -C "$cwt" add -A && git -C "$cwt" commit -qm "unit edits a.js"
chwt="$STORE/.orchestration/workspaces/feat-conflict"
echo "change-change" > "$chwt/a.js"; git -C "$chwt" add -A && git -C "$chwt" commit -qm "change branch edits a.js too"
$RC unit set --store teststore --name feat-conflict --unit a status reviewed
merge1_out="$($RC unit merge --store teststore --project "$MPROJECT" --name feat-conflict --unit a 2>&1; echo "EXIT:$?")"
check "merge attempt 1 (conflict) exits 3" test "${merge1_out##*EXIT:}" = 3
case "$merge1_out" in *a.js*) echo "ok   merge attempt 1 prints the conflicting file" ;; *) echo "FAIL merge attempt 1 prints the conflicting file (got: $merge1_out)"; fails=$((fails+1)) ;; esac
check_out "status after first conflict is 'conflict'" "status: conflict" $RC unit get --store teststore --name feat-conflict --unit a
$RC unit set --store teststore --name feat-conflict --unit a status resolving
merge2_out="$($RC unit merge --store teststore --project "$MPROJECT" --name feat-conflict --unit a 2>&1; echo "EXIT:$?")"
check "merge attempt 2 (second conflict) exits 3" test "${merge2_out##*EXIT:}" = 3
case "$merge2_out" in *a.js*) echo "ok   merge attempt 2 prints the conflicting file" ;; *) echo "FAIL merge attempt 2 prints the conflicting file (got: $merge2_out)"; fails=$((fails+1)) ;; esac
check_out "status after second conflict is 'failed'" "status: failed" $RC unit get --store teststore --name feat-conflict --unit a
n_merge_events="$($RC session list --store teststore --name feat-conflict | grep -c 'event=merge')"
check "one event=merge entry per rebase attempt (2 total)" test "$n_merge_events" = 2

# a 'resolving' unit whose worktree still has a rebase in progress: unit
# merge aborts it and fails it outright, regardless of merge_attempts
$RC state init --store teststore --name feat-unresolved
$RC state set --store teststore --name feat-unresolved seams "s=a.js" units "a=a.js" unit_deps ""
$RC workspace create --store teststore --project "$MPROJECT" --name feat-unresolved >/dev/null 2>&1
uwt2="$($RC unit create --store teststore --project "$MPROJECT" --name feat-unresolved --unit a)"
echo "unit-change" > "$uwt2/a.js"; git -C "$uwt2" add -A && git -C "$uwt2" commit -qm "unit edits a.js"
chwt2="$STORE/.orchestration/workspaces/feat-unresolved"
echo "change-change" > "$chwt2/a.js"; git -C "$chwt2" add -A && git -C "$chwt2" commit -qm "change edits a.js too"
$RC unit set --store teststore --name feat-unresolved --unit a status resolving
git -C "$uwt2" rebase change/feat-unresolved >/dev/null 2>&1 || true
check "merge: unfinished rebase aborts it and fails, exit 3" bash -c "$RC unit merge --store teststore --project '$MPROJECT' --name feat-unresolved --unit a >/dev/null 2>&1; [ \$? -eq 3 ]"
check_out "status failed regardless of merge_attempts" "status: failed" $RC unit get --store teststore --name feat-unresolved --unit a
check_out "an event=merge result=failed entry logged" "event=merge result=failed" $RC session list --store teststore --name feat-unresolved

# =====================================================================
# next_action at applying: the phase=applying action table
# =====================================================================
appl_init() { # <name> -- state init + seams/units baseline at phase applying
  $RC state init --store teststore --name "$1" >/dev/null
  $RC state set --store teststore --name "$1" phase applying seams "s=a.js,b.js,c.js" units "a=a.js;b=b.js;c=c.js" unit_deps "" >/dev/null
}
appl_udir() { echo "$STORE/.orchestration/state/$1.units"; }

appl_init feat-appl-split
$RC state set --store teststore --name feat-appl-split units ""
check_out "applying: empty units, full+parallel -> split at deep" "action: split" $RC next --store teststore --name feat-appl-split
check_out "applying: split tier is deep" "tier: deep" $RC next --store teststore --name feat-appl-split
out="$($RC next --store teststore --name feat-appl-split)"
case "$out" in *"running:"*) echo "FAIL applying split prints a running: line"; fails=$((fails+1)) ;; *) echo "ok   applying split prints no running: line" ;; esac

appl_init feat-appl-light
$RC state set --store teststore --name feat-appl-light lifecycle light units ""
check_out "applying: light -> split at none (units single)" "action: split" $RC next --store teststore --name feat-appl-light
check_out "applying: light split is tier none" "tier: none" $RC next --store teststore --name feat-appl-light
check_out "applying: light split names units single" "units single" $RC next --store teststore --name feat-appl-light

appl_init feat-appl-parallelfalse
$RC state set --store teststore --name feat-appl-parallelfalse parallel false units ""
check_out "applying: parallel false -> split at none" "action: split" $RC next --store teststore --name feat-appl-parallelfalse
check_out "applying: parallel false split is tier none" "tier: none" $RC next --store teststore --name feat-appl-parallelfalse

mkdir -p "$TMP/store-pf/openspec"
cat >> "$OPENSPEC_STORE_REGISTRY" <<EOF
  store-pf:
    local_path: $TMP/store-pf
EOF
cat > "$TMP/store-pf/openspec/config.yaml" <<'EOF'
orchestration:
  concurrency: 2
  parallel: false
  gate_quick: "echo QUICK-OK in $PWD"
  gate_full: "echo FULL-OK in $PWD"
EOF
$RC state init --store store-pf --name feat-pf
$RC state set --store store-pf --name feat-pf phase applying seams "s=a.js" units ""
check_out "applying: store orchestration.parallel false -> split at none" "tier: none" $RC next --store store-pf --name feat-pf

appl_init feat-appl-badparallel
$RC state set --store teststore --name feat-appl-badparallel parallel maybe units ""
check_out "applying: parallel maybe errors" "unknown parallel" bash -c "$RC next --store teststore --name feat-appl-badparallel 2>&1; true"

appl_init feat-appl-checkfail
$RC state set --store teststore --name feat-appl-checkfail units "a=a.js;b=a.js" unit_deps ""
check_out "applying: units check failing -> non-zero" "no dep path" bash -c "$RC next --store teststore --name feat-appl-checkfail 2>&1; true"

appl_init feat-appl-failed
udir="$(appl_udir feat-appl-failed)"; mkdir -p "$udir"
cat > "$udir/a.yaml" <<'EOF'
status: failed
iterations: 5
EOF
check_out "applying: a failed unit -> gate1" "action: gate1" $RC next --store teststore --name feat-appl-failed
check_out "applying: gate1 for a failed unit names it" "a" $RC next --store teststore --name feat-appl-failed

appl_init feat-appl-conflict
udir="$(appl_udir feat-appl-conflict)"; mkdir -p "$udir"
cat > "$udir/a.yaml" <<'EOF'
status: conflict
iterations: 1
EOF
check_out "applying: a conflict unit -> merge-conflict" "action: merge-conflict" $RC next --store teststore --name feat-appl-conflict
check_out "applying: merge-conflict tier is standard" "tier: standard" $RC next --store teststore --name feat-appl-conflict
check_out "applying: merge-conflict names the unit" "units: a" $RC next --store teststore --name feat-appl-conflict

appl_init feat-appl-revise
udir="$(appl_udir feat-appl-revise)"; mkdir -p "$udir"
cat > "$udir/a.yaml" <<'EOF'
status: reviewing
iterations: 2
critique: blocking:1
EOF
check_out "applying: reviewing+blocking under the cap -> unit-revise" "action: unit-revise" $RC next --store teststore --name feat-appl-revise
cat > "$udir/a.yaml" <<'EOF'
status: reviewing
iterations: 5
critique: blocking:1
EOF
check_out "applying: reviewing+blocking at the cap -> gate1" "action: gate1" $RC next --store teststore --name feat-appl-revise

appl_init feat-appl-merge
$RC state set --store teststore --name feat-appl-merge unit_deps "b=a;c=a"
udir="$(appl_udir feat-appl-merge)"; mkdir -p "$udir"
cat > "$udir/a.yaml" <<'EOF'
status: merged
iterations: 5
EOF
cat > "$udir/b.yaml" <<'EOF'
status: reviewed
iterations: 3
EOF
cat > "$udir/c.yaml" <<'EOF'
status: reviewed
iterations: 3
EOF
check_out "applying: reviewed units with merged deps -> unit-merge" "action: unit-merge" $RC next --store teststore --name feat-appl-merge
check_out "applying: unit-merge lists units in merge order" "units: b c" $RC next --store teststore --name feat-appl-merge

appl_init feat-appl-critique
$RC session append --store teststore --name feat-appl-critique role worker phase proposed tier deep model claude-opus-5-plain transcript_id q1
udir="$(appl_udir feat-appl-critique)"; mkdir -p "$udir"
cat > "$udir/a.yaml" <<'EOF'
status: green
tier: standard
iterations: 3
critique: ""
EOF
cat > "$udir/b.yaml" <<'EOF'
status: running
iterations: 1
EOF
cat > "$udir/c.yaml" <<'EOF'
status: green
tier: deep
iterations: 1
critique: ""
EOF
# teststore maps standard, deep and max all onto claude-opus-5-custom, so a
# standard worker's tier-above checker is its own model: refused without
# checker_effort, accepted with it.
check_out "applying: unit-critique with the worker's model at the tier above is refused" "own model" bash -c "$RC next --store teststore --name feat-appl-critique 2>&1; true"
cat >> "$STORE/openspec/config.yaml" <<'EOF'
  checker_effort: high
EOF
check_out "applying: green unit with no critique -> unit-critique" "action: unit-critique" $RC next --store teststore --name feat-appl-critique
check_out "applying: unit-critique tier is one above the unit's own standard worker, not the proposer" "tier: deep" $RC next --store teststore --name feat-appl-critique
check_out "applying: unit-critique prints the configured checker effort" "effort: high" $RC next --store teststore --name feat-appl-critique
out_uc="$($RC next --store teststore --name feat-appl-critique)"
case "$out_uc" in *"overlay:"*) echo "FAIL applying: unit-critique prints no overlay when only critic.md exists"; fails=$((fails+1)) ;; *) echo "ok   applying: unit-critique prints no overlay when only critic.md exists" ;; esac
printf 'Open the screenshot before reading the diff.\n' > "$STORE/openspec/roles/unit-critic.md"
check_out "applying: unit-critique names the unit-critic overlay" "overlay: $STORE/openspec/roles/unit-critic.md" $RC next --store teststore --name feat-appl-critique
check_out "applying: unit-critique groups only units at the same worker tier" "units: a" $RC next --store teststore --name feat-appl-critique
check_out "applying: unit-critique still reports the running unit" "running: b" $RC next --store teststore --name feat-appl-critique
cat > "$udir/a.yaml" <<'EOF'
status: merged
tier: standard
iterations: 3
critique: clean
EOF
check_out "applying: a deep foundation unit is critiqued at max" "tier: max" $RC next --store teststore --name feat-appl-critique
check_out "applying: the deep unit is dispatched on its own" "units: c" $RC next --store teststore --name feat-appl-critique
check_out "model verify with checker_effort accepts the same model" "claude-opus-5-custom" $RC model verify --store teststore --name feat-verify

# light lifecycle: a non-UI standard leaf green on iteration 1 skips the critic
appl_init feat-appl-pass
$RC state set --store teststore --name feat-appl-pass lifecycle light units "all=a.js,b.js,c.js" unit_deps "" ui_units ""
udir="$(appl_udir feat-appl-pass)"; mkdir -p "$udir"
cat > "$udir/all.yaml" <<'EOF'
status: green
tier: standard
iterations: 1
critique: ""
EOF
check_out "applying: light leaf green on iteration 1 -> unit-pass" "action: unit-pass" $RC next --store teststore --name feat-appl-pass
check_out "applying: unit-pass is tier none" "tier: none" $RC next --store teststore --name feat-appl-pass
check_out "applying: unit-pass names the unit" "units: all" $RC next --store teststore --name feat-appl-pass
check "unit pass succeeds for the eligible unit" $RC unit pass --store teststore --name feat-appl-pass --unit all
check_out "unit pass marks the unit reviewed" "status: reviewed" $RC unit get --store teststore --name feat-appl-pass --unit all
check_out "unit pass records critique skipped" "critique: skipped" $RC unit get --store teststore --name feat-appl-pass --unit all
check_out "unit pass logs the skip with its reason" "event=critique-skipped reason=light-leaf-green-first-iteration" $RC session list --store teststore --name feat-appl-pass
check_out "applying: a passed unit proceeds to unit-merge" "action: unit-merge" $RC next --store teststore --name feat-appl-pass
check_out "unit pass refuses a second time" "is not green" bash -c "$RC unit pass --store teststore --name feat-appl-pass --unit all 2>&1; true"

appl_init feat-appl-pass2
$RC state set --store teststore --name feat-appl-pass2 lifecycle light units "all=a.js" unit_deps "" ui_units ""
udir="$(appl_udir feat-appl-pass2)"; mkdir -p "$udir"
printf 'status: green\ntier: standard\niterations: 2\ncritique: ""\n' > "$udir/all.yaml"
check_out "applying: light leaf needing 2 iterations keeps its critic" "action: unit-critique" $RC next --store teststore --name feat-appl-pass2
check_out "unit pass refuses a unit that took more than one iteration" "not 1" bash -c "$RC unit pass --store teststore --name feat-appl-pass2 --unit all 2>&1; true"
printf 'status: green\ntier: standard\niterations: 1\ncritique: ""\n' > "$udir/all.yaml"
$RC state set --store teststore --name feat-appl-pass2 ui_units "all"
check_out "applying: light UI unit keeps its critic" "action: unit-critique" $RC next --store teststore --name feat-appl-pass2
check_out "unit pass refuses a UI unit" "UI unit" bash -c "$RC unit pass --store teststore --name feat-appl-pass2 --unit all 2>&1; true"
$RC state set --store teststore --name feat-appl-pass2 ui_units "" lifecycle full
check_out "applying: full lifecycle never skips the unit critic" "action: unit-critique" $RC next --store teststore --name feat-appl-pass2
check_out "unit pass refuses under lifecycle full" "only light" bash -c "$RC unit pass --store teststore --name feat-appl-pass2 --unit all 2>&1; true"
$RC state set --store teststore --name feat-appl-pass2 lifecycle light
printf 'status: green\ntier: deep\niterations: 1\ncritique: ""\n' > "$udir/all.yaml"
check_out "unit pass refuses a deep foundation unit" "foundation" bash -c "$RC unit pass --store teststore --name feat-appl-pass2 --unit all 2>&1; true"
check_out "model verify prints the configured checker effort" "effort: high" $RC model verify --store teststore --name feat-verify

appl_init feat-appl-spawn
check_out "applying: fresh units -> unit-spawn" "action: unit-spawn" $RC next --store teststore --name feat-appl-spawn
check_out "applying: unit-spawn is tier standard" "tier: standard" $RC next --store teststore --name feat-appl-spawn
check_out "applying: unit-spawn lists each leaf at standard" "unit_tiers: a=standard;b=standard" $RC next --store teststore --name feat-appl-spawn
check_out "applying: unit-spawn names the worker overlay" "overlay: $STORE/openspec/roles/worker.md" $RC next --store teststore --name feat-appl-spawn
check_out "applying: unit-spawn lists ready units up to capacity (2)" "units: a b" $RC next --store teststore --name feat-appl-spawn
check_out "applying: unit-spawn running line is empty" "running: " $RC next --store teststore --name feat-appl-spawn

appl_init feat-appl-chain
$RC state set --store teststore --name feat-appl-chain unit_deps "b=a;c=b"
check_out "applying: a chain link with one dependent spawns at standard" "unit_tiers: a=standard" $RC next --store teststore --name feat-appl-chain

appl_init feat-appl-found
$RC state set --store teststore --name feat-appl-found unit_deps "b=a;c=a"
check_out "applying: a unit two others depend on spawns at deep" "tier: deep" $RC next --store teststore --name feat-appl-found
check_out "applying: unit_tiers marks the foundation unit deep" "unit_tiers: a=deep" $RC next --store teststore --name feat-appl-found
check_out "applying: only the foundation unit is ready" "units: a" $RC next --store teststore --name feat-appl-found
udir="$(appl_udir feat-appl-found)"; mkdir -p "$udir"
cat > "$udir/a.yaml" <<'EOF'
status: reviewing
tier: deep
iterations: 1
critique: blocking:1
EOF
check_out "applying: unit-revise keeps the unit's recorded tier" "tier: deep" $RC next --store teststore --name feat-appl-found

appl_init feat-appl-wait
udir="$(appl_udir feat-appl-wait)"; mkdir -p "$udir"
cat > "$udir/a.yaml" <<'EOF'
status: running
iterations: 1
EOF
cat > "$udir/b.yaml" <<'EOF'
status: running
iterations: 1
EOF
check_out "applying: capacity fully held -> wait" "action: wait" $RC next --store teststore --name feat-appl-wait
check_out "applying: wait reports both running units" "running: a b" $RC next --store teststore --name feat-appl-wait

appl_init feat-appl-done
udir="$(appl_udir feat-appl-done)"; mkdir -p "$udir"
cat > "$udir/a.yaml" <<'EOF'
status: merged
EOF
cat > "$udir/b.yaml" <<'EOF'
status: merged
EOF
cat > "$udir/c.yaml" <<'EOF'
status: merged
EOF
check_out "applying: all merged -> units-merged" "action: units-merged" $RC next --store teststore --name feat-appl-done
check_out "applying: units-merged sets phase checking" "set_phase: checking" $RC next --store teststore --name feat-appl-done

# =====================================================================
# status: UNITS column, LAST_TIER ignores trailing entries without tier=
# =====================================================================
check_out "status header includes UNITS" "UNITS" $RC status --store teststore
$RC state init --store teststore --name feat-unitscol
$RC state set --store teststore --name feat-unitscol seams "s=a.js,b.js" units "a=a.js;b=b.js" unit_deps ""
mkdir -p "$STORE/.orchestration/state/feat-unitscol.units"
cat > "$STORE/.orchestration/state/feat-unitscol.units/a.yaml" <<'EOF'
status: merged
EOF
cat > "$STORE/.orchestration/state/feat-unitscol.units/b.yaml" <<'EOF'
status: running
EOF
check_out "status shows 1/2 for one of two units merged" "1/2" $RC status --store teststore
$RC session append --store teststore --name feat-unitscol role worker phase unit unit a event iterate tier standard model claude-sonnet-5
$RC session append --store teststore --name feat-unitscol role orchestrator phase unit unit a event merge result merged
out_status="$($RC status --store teststore)"
line_unitscol="$(printf '%s\n' "$out_status" | grep feat-unitscol)"
case "$line_unitscol" in
  *standard*) echo "ok   LAST_TIER ignores a trailing entry with no tier=" ;;
  *) echo "FAIL LAST_TIER ignores a trailing entry with no tier= (got: $line_unitscol)"; fails=$((fails+1)) ;;
esac
$RC state init --store teststore --name feat-nounits
case "$($RC status --store teststore | grep feat-nounits)" in
  *" - "*) echo "ok   status shows - in UNITS for a change without units" ;;
  *) echo "FAIL status shows - in UNITS for a change without units"; fails=$((fails+1)) ;;
esac

# =====================================================================
# docs: style-split rule and role-prompt vocabulary documented where an
# editor would look (AUTONOMOUS-ORCHESTRATION.md, CONTEXT.md, config.yaml,
# SKILL.md) — see specs/role-prompts/spec.md "Style split documented"
# =====================================================================
hr_line="$(grep -n '^## Hard rule: written for agents' $SKILL/AUTONOMOUS-ORCHESTRATION.md | head -1 | cut -d: -f1)"
ro_line="$(grep -n '^### Role overlays' $SKILL/AUTONOMOUS-ORCHESTRATION.md | head -1 | cut -d: -f1)"
fr_line="$(grep -n '^### Fix rounds' $SKILL/AUTONOMOUS-ORCHESTRATION.md | head -1 | cut -d: -f1)"
hr_hit=""; ro_hit=""
for n in $(grep -n 'scripts/roles' $SKILL/AUTONOMOUS-ORCHESTRATION.md | cut -d: -f1); do
  [ -n "$hr_line" ] && [ "$n" -gt "$hr_line" ] && hr_hit=1
  [ -n "$ro_line" ] && [ -n "$fr_line" ] && [ "$n" -gt "$ro_line" ] && [ "$n" -lt "$fr_line" ] && ro_hit=1
done
check "$SKILL/AUTONOMOUS-ORCHESTRATION.md names scripts/roles in the Hard rule section" test -n "$hr_hit"
check "$SKILL/AUTONOMOUS-ORCHESTRATION.md names scripts/roles in the Role overlays section" test -n "$ro_hit"

check "$SKILL/CONTEXT.md defines Role prompt" bash -c "grep -qE -- '\*\*Role prompt\*\*' $SKILL/CONTEXT.md"
check "$SKILL/CONTEXT.md defines Anchor" bash -c "grep -qE -- '\*\*Anchor\*\*' $SKILL/CONTEXT.md"
anchor_start="$(grep -n -- '\*\*Anchor\*\*' $SKILL/CONTEXT.md | head -1 | cut -d: -f1)"
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

ctx_line="$(grep -n '^context:' openspec/config.yaml | head -1 | cut -d: -f1)"
next_key_line="$(awk -v s="${ctx_line:-0}" 'NR>s && /^[a-zA-Z_]+:/{print NR; exit}' openspec/config.yaml)"
cfg_hit="$(grep -n 'scripts/roles/<role>.md' openspec/config.yaml | head -1 | cut -d: -f1)"
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

gm_start="$({ grep -n '^## Grill mode$' $SKILL/SKILL.md || true; } | head -1 | cut -d: -f1)"
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

ao_start="$({ grep -n '^## Autonomous only$' $SKILL/SKILL.md || true; } | head -1 | cut -d: -f1)"
ao_tmp="$TMP/autonomous_only_section.txt"
awk -v s="${ao_start:-0}" 'NR==s{print;started=1;next} started{ if (/^## /) exit; print }' $SKILL/SKILL.md > "$ao_tmp"
check "SKILL.md Autonomous only section names grill mode" grep -qF -- "grill mode" "$ao_tmp"

gr_start="$({ grep -n '^## Guardrails$' $SKILL/SKILL.md || true; } | head -1 | cut -d: -f1)"
gr_tmp="$TMP/guardrails_section.txt"
awk -v s="${gr_start:-0}" 'NR>=s{print}' $SKILL/SKILL.md > "$gr_tmp"
check "SKILL.md Guardrails section names Project glossary" grep -qF -- "Project glossary" "$gr_tmp"
check "SKILL.md Guardrails section names grill mode" grep -qF -- "grill mode" "$gr_tmp"

skill_desc="$(sed -n 's/^description: //p' $SKILL/SKILL.md | head -1)"
catalog_desc="$(sed -n 's/.*"description": "\(.*\)",$/\1/p' atlas-catalog.json | head -1)"
check "SKILL.md and atlas-catalog.json descriptions are identical" test "$skill_desc" = "$catalog_desc"
case "$skill_desc" in
  *"grill mode"*) echo "ok   SKILL.md description names grill mode" ;;
  *) echo "FAIL SKILL.md description names grill mode"; fails=$((fails+1)) ;;
esac

desc_full="$({ grep '^description: ' $SKILL/SKILL.md || true; } | head -1)"
colon_count="$(printf '%s\n' "$desc_full" | { grep -o ': ' || true; } | wc -l | tr -d ' ')"
hash_count="$(printf '%s\n' "$desc_full" | { grep -o ' #' || true; } | wc -l | tr -d ' ')"
check "SKILL.md description: line has exactly one ': '" test "$colon_count" = 1
check "SKILL.md description: line has no ' #'" test "$hash_count" = 0

check "CONTEXT.md defines Project glossary" grep -qF -- '**Project glossary**' $SKILL/CONTEXT.md
check "CONTEXT.md defines Implied baseline" grep -qF -- '**Implied baseline**' $SKILL/CONTEXT.md
check "SKILL.md grill section never asks the obvious" grep -qF -- 'Never ask the obvious' $SKILL/SKILL.md
check "AUTONOMOUS-ORCHESTRATION.md fidelity standard names the implied baseline" bash -c "grep -A4 -- '- \*\*Fidelity\*\*' $SKILL/AUTONOMOUS-ORCHESTRATION.md | grep -q 'implied baseline'"
check "CONTEXT.md defines Grill mode" grep -qF -- '**Grill mode**' $SKILL/CONTEXT.md
cic_start="$({ grep -n -- '\*\*Checker input contract\*\*' $SKILL/CONTEXT.md || true; } | head -1 | cut -d: -f1)"
cic_tmp="$TMP/checker_input_contract.txt"
awk -v s="${cic_start:-0}" 'NR==s{print;started=1;next} started{ if (/^- \*\*/) exit; print }' $SKILL/CONTEXT.md > "$cic_tmp"
check "CONTEXT.md Checker input contract entry names Project glossary" grep -qF -- "Project glossary" "$cic_tmp"

ctx2_line="$(grep -n '^context:' openspec/config.yaml | head -1 | cut -d: -f1)"
ctx2_next="$(awk -v s="${ctx2_line:-0}" 'NR>s && /^[a-zA-Z_]+:/{print NR; exit}' openspec/config.yaml)"
ctx2_hit="$({ grep -n 'openspec/CONTEXT.md' openspec/config.yaml || true; } | head -1 | cut -d: -f1)"
check "openspec/config.yaml names openspec/CONTEXT.md inside the context: block" \
  bash -c "[ -n '${ctx2_hit:-}' ] && [ -n '${ctx2_line:-}' ] && [ -n '${ctx2_next:-}' ] && [ '$ctx2_hit' -gt '$ctx2_line' ] && [ '$ctx2_hit' -lt '$ctx2_next' ]"

check "README names /openspec-orchestrator grill" grep -qF -- "/openspec-orchestrator grill" README.md
readme_ctx_row="$({ grep -F '[`CONTEXT.md`]' README.md || true; } | head -1)"
case "$readme_ctx_row" in
  *"openspec/CONTEXT.md"*) echo "ok   README CONTEXT.md layout row names openspec/CONTEXT.md" ;;
  *) echo "FAIL README CONTEXT.md layout row names openspec/CONTEXT.md"; fails=$((fails+1)) ;;
esac

crit_start="$({ grep -n -- '\*\*Critique\*\*' $SKILL/AUTONOMOUS-ORCHESTRATION.md || true; } | head -1 | cut -d: -f1)"
crit_end="$({ grep -n -- 'The critic writes a \*\*critique report\*\*' $SKILL/AUTONOMOUS-ORCHESTRATION.md || true; } | head -1 | cut -d: -f1)"
crit_tmp="$TMP/critique_contract.txt"
awk -v s="${crit_start:-0}" -v e="${crit_end:-0}" 'NR>=s && NR<=e' $SKILL/AUTONOMOUS-ORCHESTRATION.md > "$crit_tmp"
check "AUTONOMOUS-ORCHESTRATION.md Critique input contract names openspec/CONTEXT.md" grep -qF -- "openspec/CONTEXT.md" "$crit_tmp"
check "AUTONOMOUS-ORCHESTRATION.md Critique input contract names openspec/adr/" grep -qF -- "openspec/adr/" "$crit_tmp"

echo
[ "$fails" -eq 0 ] && echo "all tests passed" || { echo "$fails test(s) failed"; exit 1; }
