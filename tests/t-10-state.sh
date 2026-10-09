#!/usr/bin/env bash
# State, session log, status, slots, workspace, gates, model routing, overlays, initiatives.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
teststore
mkorigin

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
check_err "direct session append of role advisor is refused" "reserved" $RC session append --store teststore --name feat-a role advisor tier deep model x
check_out "advisor request grants and prints deep model" "claude-opus-5" $RC advisor request --store teststore --name feat-a --worker w1
check_out "status counts advisor calls" "1/2" $RC status --store teststore
check_err "second request from same worker refused" "already used its one advisor call" $RC advisor request --store teststore --name feat-a --worker w1
check_out "request from another worker granted" "claude-opus-5" $RC advisor request --store teststore --name feat-a --worker w2
check_err "third request hits the per-change cap" "advisor cap reached" $RC advisor request --store teststore --name feat-a --worker w3
check_out "status shows cap reached" "2/2" $RC status --store teststore
check_out "advisor entry records the asking worker" "role=advisor tier=deep model=claude-opus-5-5 for=w1" $RC session list --store teststore --name feat-a

# slots (cap=2 from store config)
s1="$($RC slot acquire --store teststore --project "$PROJECT")"
s2="$($RC slot acquire --store teststore --project "$PROJECT")"
check_err "third slot refused at cap" "no free slot" $RC slot acquire --store teststore --project "$PROJECT"
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
check_err "gate run without a workspace errors" "no workspace for change" $RC gate run --store teststore --project "$PROJECT" --name feat-none --mode quick
$RC workspace remove --store teststore --project "$PROJECT" --name feat-a
check "workspace removed" test ! -e "$wt"
check_fails "branch removed" git -C "$PROJECT" rev-parse --verify -q change/feat-a

# gates (config read from the store, project has no openspec/)

# tier -> model
check_out "model get falls back to default for mechanical" "claude-haiku-5-5" $RC model get --store teststore --tier mechanical
check_out "model get falls back to default for deep" "claude-opus-5" $RC model get --store teststore --tier deep
cat >> "$STORE/openspec/config.yaml" <<'EOF'
  model_deep: "claude-opus-5-custom"
EOF
check_out "model get honors store override" "claude-opus-5-custom" $RC model get --store teststore --tier deep

# stage -> project skill(s) (docs/proposals/skill-stage-mapping.md)
check_out "stage-skills get is empty when stage_skills is unset" "" $RC stage-skills get --store teststore --stage plan

# role overlays: <store>/openspec/roles/<role>.md, text printed verbatim
check_out "roles get with no overlay prints nothing" "" $RC roles get --store teststore --role critic
check "roles get with no overlay exits 0" $RC roles get --store teststore --role critic
check_err "roles get refuses an unknown role" "unknown role" $RC roles get --store teststore --role reviewer
check_fails "roles get with an unknown role exits non-zero" $RC roles get --store teststore --role reviewer
check "roles prompt with no overlay exits 0" $RC roles prompt --store teststore --role verifier
check "roles prompt with no overlay prints exactly the engine prompt" bash -c "diff <($RC roles prompt --store teststore --role verifier) $SKILL/scripts/roles/verifier.md"
check_err "roles prompt refuses an unknown role" "unknown role" $RC roles prompt --store teststore --role reviewer
check_fails "roles prompt with an unknown role exits non-zero" $RC roles prompt --store teststore --role reviewer
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
check_out "model verify first line is the bare model id" "claude-opus-5-custom" bash -c "$RC model verify --store teststore --name feat-verify | sed -n 1p"
check_out "model verify contract mentions input and seam" "input:" $RC model verify --store teststore --name feat-verify
check_out "model verify contract names the store config as an input" "$STORE/openspec/config.yaml" $RC model verify --store teststore --name feat-verify
check_out "model verify contract makes a stale config a warning" "else one warning finding" $RC model verify --store teststore --name feat-verify
check "model verify contract names no Project glossary or ADRs" bash -c "out=\"\$($RC model verify --store teststore --name feat-verify)\" && case \"\$out\" in *openspec/CONTEXT.md*|*openspec/adr/*) exit 1 ;; esac"
out_cc="$($RC model critic --store teststore --name feat-critic 2>/dev/null || true)"
case "$out_cc" in *"config.yaml"*) echo "FAIL model critic contract does not name the store config"; fails=$((fails+1)) ;; *) echo "ok   model critic contract does not name the store config" ;; esac
$RC session append --store teststore --name feat-infer role worker phase applying model claude-sonnet-5-5 transcript_id t1
check_out "model verify infers the tier from the model when an entry has none" "claude-opus-5-custom" $RC model verify --store teststore --name feat-infer
cat >> "$STORE/openspec/config.yaml" <<'EOF'
  model_standard: "claude-opus-5-custom"
EOF
check_err "model verify errors when a tier-less entry's model maps to no tier" "cannot tell which tier" $RC model verify --store teststore --name feat-infer
$RC session append --store teststore --name feat-verify role worker phase applying tier deep model claude-opus-5-custom transcript_id t2
check_out "model verify for a deep implementer goes to max" "claude-fable-5-1" $RC model verify --store teststore --name feat-verify
cat >> "$STORE/openspec/config.yaml" <<'EOF'
  model_max: "claude-opus-5-custom"
EOF
check_err "model verify errors when the tier above resolves to the implementer's model" "resolves to the implementer's own model" $RC model verify --store teststore --name feat-verify

# generator/checker split at Propose: the critic is one tier above the proposer
$RC state init --store teststore --name feat-critic
check_out "state init has propose_rounds" "propose_rounds: 0" $RC state get --store teststore --name feat-critic
$RC session append --store teststore --name feat-critic role worker phase proposed tier deep model claude-opus-5-custom transcript_id t1
check_err "model critic errors when max resolves to the proposer's model" "resolves to the proposer's own model" $RC model critic --store teststore --name feat-critic
$RC session append --store teststore --name feat-critic role worker phase proposed tier deep model some-other-model transcript_id t2
check_out "model critic uses max for a deep proposer" "claude-opus-5-custom" $RC model critic --store teststore --name feat-critic
$RC session append --store teststore --name feat-critic role worker phase applying tier standard model claude-opus-5-custom transcript_id t3
check_out "model critic ignores non-proposed entries" "claude-opus-5-custom" $RC model critic --store teststore --name feat-critic
$RC session append --store teststore --name feat-critic role worker phase proposed tier max model claude-fable-5-1 transcript_id t4
check_out "model critic for a max proposer drops to deep, the second highest" "claude-opus-5-custom" $RC model critic --store teststore --name feat-critic
$RC session append --store teststore --name feat-critic role worker phase proposed tier max model claude-opus-5-custom transcript_id t5
check_err "model critic errors when deep resolves to a max proposer's model" "resolves to the proposer's own model" $RC model critic --store teststore --name feat-critic
$RC session append --store teststore --name feat-critic role worker phase proposed tier standard model claude-sonnet-5 transcript_id t6
check_out "model critic first line is the bare model id" "claude-opus-5-custom" bash -c "$RC model critic --store teststore --name feat-critic | sed -n 1p"
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
check_fails "initiative is not a change state file" test -f '$STORE/.orchestration/state/init-a.yaml'
check_out "status shows initiative tree" "init-a" $RC status --store teststore
check_out "status shows started child phase" "feat-a" $RC status --store teststore
check_out "status shows unstarted child" "not-started" $RC status --store teststore
$RC session append --store teststore --name init-a role worker phase proposed tier deep model claude-opus-5-custom transcript_id t9
check_err "model critic works for an initiative name" "resolves to the proposer's own model" $RC model critic --store teststore --name init-a
$RC session append --store teststore --name init-a role worker phase proposed tier deep model claude-opus-5-other transcript_id t10
check_out "model critic for an initiative (no change state file) prints the contract" "input:" $RC model critic --store teststore --name init-a
check_err "initiative merged refuses unlisted child" "not a child" $RC initiative merged --store teststore --name init-a --child feat-zzz --commit abc
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
check_err "next: unknown lifecycle errors" "unknown lifecycle" $RC next --store teststore --name feat-bogus-lifecycle

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

finish
