#!/usr/bin/env bash
# unit iterate: engine-run checks, escalation by evidence, gate_ui, revise round trip.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# =====================================================================
# unit iterate: engine-run checks, capped, session-logged
# =====================================================================
mkstore storeu1 >/dev/null <<'EOF'
orchestration:
  concurrency: 2
  unit_concurrency: 2
  gate_quick: 'test -f OK && { [ -z "$UNIT_SCREENSHOT" ] || touch "$UNIT_SCREENSHOT"; }'
  gate_full: "echo FULL-OK in $PWD"
EOF
UPROJECT1="$TMP/uproject1"
mkproject "$UPROJECT1" a.js

$RC state init --store storeu1 --name feat-iter
$RC state set --store storeu1 --name feat-iter seams "s=a.js" units "a=a.js" unit_deps "" ui_units "a"
$RC workspace create --store storeu1 --project "$UPROJECT1" --name feat-iter >/dev/null 2>&1
iwt="$($RC unit create --store storeu1 --project "$UPROJECT1" --name feat-iter --unit a)"
echo check > "$iwt/a.test.js"; git -C "$iwt" add -A && git -C "$iwt" commit -qm checks
$RC unit checks-done --store storeu1 --project "$UPROJECT1" --name feat-iter --unit a

# escalation by evidence: red, red -> advisor required; red after advice -> failed to Gate 1
check_fails "unit iterate #1 returns red (no OK file yet)" $RC unit iterate --store storeu1 --project "$UPROJECT1" --name feat-iter --unit a
check_out "first red records reds_in_row 1" "reds_in_row: 1" $RC unit get --store storeu1 --name feat-iter --unit a
check_err "unit iterate #2 returns red and demands the advisor" "advisor required" $RC unit iterate --store storeu1 --project "$UPROJECT1" --name feat-iter --unit a
check_out "second red records reds_in_row 2" "reds_in_row: 2" $RC unit get --store storeu1 --name feat-iter --unit a
nlines_before="$($RC session list --store storeu1 --name feat-iter | wc -l | tr -d ' ')"
check_err "third iterate is refused until the advisor is asked" "advisor required first" $RC unit iterate --store storeu1 --project "$UPROJECT1" --name feat-iter --unit a
nlines_after="$($RC session list --store storeu1 --name feat-iter | wc -l | tr -d ' ')"
check "refused iterate logs nothing" test "$nlines_before" = "$nlines_after"
check_out "unit still running while waiting on the advisor" "status: running" $RC unit get --store storeu1 --name feat-iter --unit a
check_out "advisor request --unit grants and prints the deep model" "claude-opus-5" $RC advisor request --store storeu1 --name feat-iter --unit a --worker iter-w1
check_out "advisor request --unit records advised at the current iteration" "advised: 2" $RC unit get --store storeu1 --name feat-iter --unit a
check_out "advisor entry names the unit" "role=advisor tier=deep model=claude-opus-5-5 for=iter-w1 unit=a" $RC session list --store storeu1 --name feat-iter
check_fails "advisor request --unit on an unknown unit is refused" $RC advisor request --store storeu1 --name feat-iter --unit zz --worker w9
check_err "iterate after advice, still red -> escalates" "escalating to Gate 1" $RC unit iterate --store storeu1 --project "$UPROJECT1" --name feat-iter --unit a
check_out "unit failed with fail_reason red-after-advice" "fail_reason: red-after-advice" $RC unit get --store storeu1 --name feat-iter --unit a
check_out "unit status failed before the cap" "status: failed" $RC unit get --store storeu1 --name feat-iter --unit a
n_red="$($RC session list --store storeu1 --name feat-iter | grep -c 'checks=red')"
check "exactly 3 red iterate entries logged" test "$n_red" = 3
check_out "iterate entries carry tier standard" "tier=standard" $RC session list --store storeu1 --name feat-iter
check_out "unit create records the leaf's tier" "tier: standard" $RC unit get --store storeu1 --name feat-iter --unit a
$RC state set --store storeu1 --name feat-iter phase applying
check_out "next: red-after-advice unit -> gate1 with the advisor's answer" "still red after the advisor's answer" $RC next --store storeu1 --name feat-iter

# a green resets the streak; the cap stays the ceiling for alternating runs
$RC state set --store storeu1 --name feat-iter units "a=a.js;c=c.js" seams "s=a.js,c.js" phase proposed
cwt="$($RC unit create --store storeu1 --project "$UPROJECT1" --name feat-iter --unit c)"
echo check > "$cwt/c.test.js"; git -C "$cwt" add -A && git -C "$cwt" commit -qm checks
$RC unit checks-done --store storeu1 --project "$UPROJECT1" --name feat-iter --unit c
check_fails "c #1 red" $RC unit iterate --store storeu1 --project "$UPROJECT1" --name feat-iter --unit c
touch "$cwt/OK"
check "c #2 green" $RC unit iterate --store storeu1 --project "$UPROJECT1" --name feat-iter --unit c
check_out "a green resets reds_in_row" "reds_in_row: 0" $RC unit get --store storeu1 --name feat-iter --unit c
check_out "screenshot recorded as the absolute iteration-2 path" "$TMP/storeu1/.orchestration/state/feat-iter.units/c/screenshot-2.png" $RC unit get --store storeu1 --name feat-iter --unit c
rm "$cwt/OK"
check_fails "c #3 red (streak restarts at 1)" $RC unit iterate --store storeu1 --project "$UPROJECT1" --name feat-iter --unit c
touch "$cwt/OK"
check "c #4 green" $RC unit iterate --store storeu1 --project "$UPROJECT1" --name feat-iter --unit c
rm "$cwt/OK"
check_fails "c #5 red hits the cap" $RC unit iterate --store storeu1 --project "$UPROJECT1" --name feat-iter --unit c
check_out "cap failure records fail_reason iteration-cap" "fail_reason: iteration-cap" $RC unit get --store storeu1 --name feat-iter --unit c
nlines_before="$($RC session list --store storeu1 --name feat-iter | wc -l | tr -d ' ')"
check_fails "6th iterate is refused" $RC unit iterate --store storeu1 --project "$UPROJECT1" --name feat-iter --unit c
check_err "6th iterate names the iteration cap" "iteration cap" $RC unit iterate --store storeu1 --project "$UPROJECT1" --name feat-iter --unit c
nlines_after="$($RC session list --store storeu1 --name feat-iter | wc -l | tr -d ' ')"
check "6th iterate appends no log entry" test "$nlines_before" = "$nlines_after"
check_out "unit status is failed past the cap" "status: failed" $RC unit get --store storeu1 --name feat-iter --unit c

# spec contradiction: the worker fails the unit itself, next gates at once
check_err "unit set refuses an unknown fail_reason" "unknown fail_reason" $RC unit set --store storeu1 --name feat-iter --unit c fail_reason tired
printf 'status: running\ntier: standard\niterations: 1\ncritique: ""\n' > "$TMP/storeu1/.orchestration/state/feat-iter.units/a.yaml"
check "unit set accepts fail_reason spec" $RC unit set --store storeu1 --name feat-iter --unit a status failed fail_reason spec
$RC state set --store storeu1 --name feat-iter phase applying
check_out "next: spec-contradiction unit -> gate1 naming the spec" "contradicts the spec" $RC next --store storeu1 --name feat-iter

# gate_ui: runs after gate_quick for UI units only
mkstore storeui >/dev/null <<'EOF'
orchestration:
  unit_concurrency: 2
  gate_quick: 'test -f OK'
  gate_ui: 'echo UI-RAN >> "$UNIT_SCREENSHOT.log" && touch "$UNIT_SCREENSHOT"'
  gate_full: "echo FULL-OK"
EOF
UPROJECTUI="$TMP/uprojectui"
mkproject "$UPROJECTUI" a.js b.js
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
check_fails "UI unit: red gate_quick is red even when gate_ui would pass" $RC unit iterate --store storeui --project "$UPROJECTUI" --name feat-ui --unit a

# a non-UI unit red every time ends failed at the cap too
UPROJECT1B="$TMP/uproject1b"
mkproject "$UPROJECT1B" b.js
$RC state init --store storeu1 --name feat-iter-red
$RC state set --store storeu1 --name feat-iter-red seams "s=b.js" units "b=b.js" unit_deps ""
$RC workspace create --store storeu1 --project "$UPROJECT1B" --name feat-iter-red >/dev/null 2>&1
rwt="$($RC unit create --store storeu1 --project "$UPROJECT1B" --name feat-iter-red --unit b)"
echo check > "$rwt/b.test.js"; git -C "$rwt" add -A && git -C "$rwt" commit -qm checks
$RC unit checks-done --store storeu1 --project "$UPROJECT1B" --name feat-iter-red --unit b
for i in 1 2; do
  $RC unit iterate --store storeu1 --project "$UPROJECT1B" --name feat-iter-red --unit b >/dev/null 2>&1 || true
done
$RC advisor request --store storeu1 --name feat-iter-red --unit b --worker red-w1 >/dev/null
$RC unit iterate --store storeu1 --project "$UPROJECT1B" --name feat-iter-red --unit b >/dev/null 2>&1 || true
check_out "non-UI unit red after advice -> failed" "status: failed" $RC unit get --store storeu1 --name feat-iter-red --unit b
check_out "non-UI unit failed on the third iteration, not the fifth" "iterations: 3" $RC unit get --store storeu1 --name feat-iter-red --unit b

# unit-revise round trip (V2): blocking critique -> orchestrator clears it
# (status running, critique "") -> iterate green again -> unit-critique
UPROJECT1C="$TMP/uproject1c"
mkproject "$UPROJECT1C" c.js
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

finish
