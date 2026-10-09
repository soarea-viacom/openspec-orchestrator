#!/usr/bin/env bash
# next at phase applying: the action table.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
teststore
pin_models_custom
# feat-verify: a deep implementer, so the tier-above checker resolves to its own model
$RC session append --store teststore --name feat-verify role worker phase applying tier deep model claude-opus-5-custom transcript_id t2

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

mkstore store-pf >/dev/null <<'EOF'
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
check_err "applying: parallel maybe errors" "unknown parallel" $RC next --store teststore --name feat-appl-badparallel

appl_init feat-appl-checkfail
$RC state set --store teststore --name feat-appl-checkfail units "a=a.js;b=a.js" unit_deps ""
check_err "applying: units check failing -> non-zero" "no dep path" $RC next --store teststore --name feat-appl-checkfail

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
check_err "applying: unit-critique with the worker's model at the tier above is refused" "own model" $RC next --store teststore --name feat-appl-critique
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
check_err "unit pass refuses a second time" "is not green" $RC unit pass --store teststore --name feat-appl-pass --unit all

appl_init feat-appl-pass2
$RC state set --store teststore --name feat-appl-pass2 lifecycle light units "all=a.js" unit_deps "" ui_units ""
udir="$(appl_udir feat-appl-pass2)"; mkdir -p "$udir"
printf 'status: green\ntier: standard\niterations: 2\ncritique: ""\n' > "$udir/all.yaml"
check_out "applying: light leaf needing 2 iterations keeps its critic" "action: unit-critique" $RC next --store teststore --name feat-appl-pass2
check_err "unit pass refuses a unit that took more than one iteration" "not 1" $RC unit pass --store teststore --name feat-appl-pass2 --unit all
printf 'status: green\ntier: standard\niterations: 1\ncritique: ""\n' > "$udir/all.yaml"
$RC state set --store teststore --name feat-appl-pass2 ui_units "all"
check_out "applying: light UI unit keeps its critic" "action: unit-critique" $RC next --store teststore --name feat-appl-pass2
check_err "unit pass refuses a UI unit" "UI unit" $RC unit pass --store teststore --name feat-appl-pass2 --unit all
$RC state set --store teststore --name feat-appl-pass2 ui_units "" lifecycle full
check_out "applying: full lifecycle never skips the unit critic" "action: unit-critique" $RC next --store teststore --name feat-appl-pass2
check_err "unit pass refuses under lifecycle full" "only light" $RC unit pass --store teststore --name feat-appl-pass2 --unit all
$RC state set --store teststore --name feat-appl-pass2 lifecycle light
printf 'status: green\ntier: deep\niterations: 1\ncritique: ""\n' > "$udir/all.yaml"
check_err "unit pass refuses a deep foundation unit" "foundation" $RC unit pass --store teststore --name feat-appl-pass2 --unit all
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

finish
