#!/usr/bin/env bash
# next: the orchestration policy as code, walked through every branch.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
teststore
pin_models_custom

# next: the orchestration policy as code — walk a change through the lifecycle
N="$RC next --store teststore --name feat-next"
$RC state init --store teststore --name feat-next
check_out "state init seeds pillars and grill" "pillars: \"\"" $RC state get --store teststore --name feat-next
check_out "next: fresh change -> classify first" "action: classify" $N
check_out "next: classify runs at standard" "tier: standard" $N
check_out "next: classify names the pillar vocabulary" "scope=file|seam|seams;blast=none|project|public;novelty=known|new;deps=none|dev|runtime" $N
check_line "next: classify prints the proposer prompt" "prompt: $PWD/$SKILL/scripts/roles/proposer.md" $N
check_line "next: classify names the proposer agent" "agent: openspec-proposer-standard" $N
$RC state set --store teststore --name feat-next pillars "scope=seam;blast=none;novelty=huge;deps=none"
check_err "next: unknown pillar value is refused" "unknown novelty 'huge'" $N
$RC state set --store teststore --name feat-next pillars "scope=seam;blast=none;novelty=known"
check_err "next: missing pillar is refused" "missing 'deps'" $N
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
check_out "next: critique names the critic agent at its tier" "agent: openspec-critic-" $N
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
check_out "next: check names the verifier agent for the concurrent Verify" "also_agent: openspec-verifier-" $N
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
check_err "next: manual_accept 'accepted:' with no names errors" "names no requirements" $N
$RC state set --store teststore --name feat-next manual_accept "accepted:R1"
check_out "next: manual_accept naming requirements -> archive" "action: archive" $N
$RC state set --store teststore --name feat-next manual_tasks_open 2 manual_accept yes
check_err "next: manual_accept not empty or accepted:* errors" "unknown manual_accept" $N
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
check_err "next: unknown gate result errors" "unknown last_gate_result" $N

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

finish
