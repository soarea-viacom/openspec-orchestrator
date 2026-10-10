#!/usr/bin/env bash
# Units: split checks, size cap, scheduler, merge order, per-unit worktrees, unit merge.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
teststore
mkorigin

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
check_fails "units check: cycle exits non-zero" $RC units check --store teststore --name feat-units

$RC state set --store teststore --name feat-units units "a=x.js;b=x.js" unit_deps ""
$RC state set --store teststore --name feat-units seams "s=x.js"
check_err "units check: unordered overlap rejected" "no dep path" $RC units check --store teststore --name feat-units
$RC state set --store teststore --name feat-units unit_deps "b=a"
check "units check: overlap ok once ordered by a dep" $RC units check --store teststore --name feat-units

$RC state set --store teststore --name feat-units units "a=x.js,y.js" unit_deps "" seams "s=x.js"
check_err "units check: file outside seams named" "y.js" $RC units check --store teststore --name feat-units

$RC state set --store teststore --name feat-units units "A_b=x.js" seams "s=x.js"
check_err "units check: bad kebab-case name rejected" "bad unit name" $RC units check --store teststore --name feat-units

$RC state set --store teststore --name feat-units units "a=x.js;b=y.js" unit_deps "" seams "s=x.js,y.js" unit_tasks "a=1.1;b=1.1"
check_err "units check: task id in two units rejected" "task '1.1'" $RC units check --store teststore --name feat-units

mkdir -p "$STORE/openspec/changes/feat-units"
cat > "$STORE/openspec/changes/feat-units/tasks.md" <<'EOF'
# Tasks
- [ ] 1.1 do thing
- [ ] 1.2 another thing
EOF
$RC state set --store teststore --name feat-units units "a=x.js" unit_deps "" seams "s=x.js,y.js" unit_tasks "a=1.1"
check_out "units check CLI: unassigned task printed" "unassigned: 1.2" $RC units check --store teststore --name feat-units
check "units check CLI exits 0 when the check passes" $RC units check --store teststore --name feat-units

# unit size cap: 8 files / 3 tasks unless unit_size_ok names the unit
$RC state init --store teststore --name feat-size
big="f1.js,f2.js,f3.js,f4.js,f5.js,f6.js,f7.js,f8.js,f9.js"
$RC state set --store teststore --name feat-size seams "s=$big,g.js" units "wiring=$big;leaf=g.js" unit_deps "" unit_tasks "wiring=1.1;leaf=1.2"
check_err "units check: a unit over the file cap is refused" "over the size cap (9 files, 1 tasks" $RC units check --store teststore --name feat-size
check_err "units check: the refusal names the remedy" "unit_size_ok wiring" $RC units check --store teststore --name feat-size
$RC state set --store teststore --name feat-size units "wiring=f1.js;leaf=g.js" unit_tasks "wiring=1.1,1.2,1.3,1.4;leaf=1.5"
check_err "units check: a unit over the task cap is refused" "1 files, 4 tasks" $RC units check --store teststore --name feat-size
$RC state set --store teststore --name feat-size unit_size_ok "wiring"
check "units check: unit_size_ok turns the refusal into a pass" $RC units check --store teststore --name feat-size
check_err "units check: unit_size_ok still warns" "allowed by unit_size_ok" $RC units check --store teststore --name feat-size
$RC state set --store teststore --name feat-size unit_size_ok "" units "wiring=f1.js,f2.js,f3.js,f4.js,f5.js,f6.js,f7.js,f8.js;leaf=g.js" unit_tasks "wiring=1.1,1.2,1.3;leaf=1.5"
check "units check: exactly at the cap passes" $RC units check --store teststore --name feat-size
mkstore store-cap >/dev/null <<'EOF'
orchestration:
  unit_max_files: 2
  unit_max_tasks: 1
  gate_quick: "true"
  gate_full: "true"
EOF
$RC state init --store store-cap --name feat-cap
$RC state set --store store-cap --name feat-cap seams "s=a.js,b.js,c.js" units "a=a.js,b.js,c.js" unit_deps "" unit_tasks "a=1.1"
check_err "units check: store overrides the file cap" "cap 2 files / 1 tasks" $RC units check --store store-cap --name feat-cap
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

mkstore teststore3 "$TMP/store3" >/dev/null <<'EOF'
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
mkstore teststore4 "$TMP/store4" >/dev/null <<'EOF'
orchestration:
  unit_concurrency: 5
  concurrency: 1
  gate_quick: "echo QUICK-OK in $PWD"
  gate_full: "echo FULL-OK in $PWD"
EOF
git clone -q "$TMP/origin" "$TMP/project4"
s4="$($RC slot acquire --store teststore4 --project "$TMP/project4")"
check_err "unit_concurrency listed first does not raise the change-level cap" "no free slot (cap=1)" $RC slot acquire --store teststore4 --project '$TMP/project4'
$RC slot release --store teststore4 --slot "$s4"
$RC state init --store teststore4 --name feat-cap4
$RC state set --store teststore4 --name feat-cap4 seams "s=a.js,b.js,c.js" units "a=a.js;b=b.js;c=c.js" unit_deps ""
check_out "unit_concurrency still read correctly when listed first" "ready: a b c" $RC units next --store teststore4 --name feat-cap4

# defaults with neither key set: 2 changes per project, 3 units per change
mkstore store-def >/dev/null <<'EOF'
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
check_err "concurrency default refuses a third slot" "no free slot (cap=2)" $RC slot acquire --store store-def --project '$TMP/project-def'

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
check_err "units merge-order: cycle errors" "cycle" $RC units merge-order --store teststore --name feat-order

# =====================================================================
# per-unit worktree + branch lifecycle
# =====================================================================
UPROJECT="$TMP/uproject"
mkproject "$UPROJECT" x.js y.js

$RC state init --store teststore --name feat-uw
$RC state set --store teststore --name feat-uw seams "s=x.js,y.js,z.js" units "a=x.js;b=y.js;c=z.js" unit_deps "b=a"
$RC workspace create --store teststore --project "$UPROJECT" --name feat-uw >/dev/null 2>&1

check_err "unit create: dep not merged refused" "not merged" $RC unit create --store teststore --project "$UPROJECT" --name feat-uw --unit b
check_fails "unit create: dep not merged creates no branch" git -C "$UPROJECT" rev-parse --verify -q change/feat-uw.b

uwt="$($RC unit create --store teststore --project "$UPROJECT" --name feat-uw --unit a)"
check "unit create: worktree exists at the expected path" test "$uwt" = "$STORE/.orchestration/workspaces/feat-uw.a"
check "unit create: branch exists" git -C "$UPROJECT" rev-parse --verify -q change/feat-uw.a
check_out "unit create: unit file has status running" "status: running" $RC unit get --store teststore --name feat-uw --unit a
basesha="$(git -C "$UPROJECT" rev-parse change/feat-uw)"
check_out "unit create: base equals change branch tip" "base: $basesha" $RC unit get --store teststore --name feat-uw --unit a

echo dirty > "$STORE/.orchestration/workspaces/feat-uw/dirty.txt"
check_err "unit create: dirty change worktree refused" "uncommitted" $RC unit create --store teststore --project "$UPROJECT" --name feat-uw --unit c
rm -f "$STORE/.orchestration/workspaces/feat-uw/dirty.txt"
check_fails "unit create: dirty-worktree refusal created no branch" git -C "$UPROJECT" rev-parse --verify -q change/feat-uw.c

check_err "unit create: second create on a running unit refused" "already exists" $RC unit create --store teststore --project "$UPROJECT" --name feat-uw --unit a

$RC unit remove --store teststore --project "$UPROJECT" --name feat-uw --unit a
check "unit remove: worktree gone" test ! -e "$uwt"
check_fails "unit remove: branch gone" git -C "$UPROJECT" rev-parse --verify -q change/feat-uw.a
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
check_fails "workspace remove: unit branch gone even though its worktree dir was already gone" git -C "$UPROJECT" rev-parse --verify -q change/feat-uw.a
rm -f "$STORE/.orchestration/state/feat-uw.units/a.yaml"

# gate run --unit: runs in the unit worktree, never writes gate_tree
$RC workspace create --store teststore --project "$UPROJECT" --name feat-uw >/dev/null 2>&1
uwt="$($RC unit create --store teststore --project "$UPROJECT" --name feat-uw --unit a)"
check_out "gate run --unit runs in the unit worktree" "$uwt" $RC gate run --store teststore --project "$UPROJECT" --name feat-uw --unit a --mode full
check_out "gate run --unit leaves gate_tree alone" 'gate_tree: ""' $RC state get --store teststore --name feat-uw

# unit checks-done / unit iterate gating
lines_before="$($RC session list --store teststore --name feat-uw 2>&1 | wc -l)"
check_err "unit iterate before checks-done is refused" "checks-done" $RC unit iterate --store teststore --project "$UPROJECT" --name feat-uw --unit a
lines_after="$($RC session list --store teststore --name feat-uw 2>&1 | wc -l)"
check "a refused iterate logs nothing" test "$lines_before" -eq "$lines_after"
check_err "checks-done at base is refused" "still equals its base" $RC unit checks-done --store teststore --project "$UPROJECT" --name feat-uw --unit a
echo check > "$uwt/a.check.js"
git -C "$uwt" add -A && git -C "$uwt" commit -qm "add checks for unit a"
$RC unit checks-done --store teststore --project "$UPROJECT" --name feat-uw --unit a
headsha="$(git -C "$uwt" rev-parse HEAD)"
check_out "checks-done records HEAD as checks_commit" "checks_commit: $headsha" $RC unit get --store teststore --name feat-uw --unit a

# =====================================================================
# unit merge: dependency-ordered, scope-checked, conflict handling
# =====================================================================
MPROJECT="$TMP/mproject"
mkproject "$MPROJECT" a.js b.js

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
check_fails "merge: unit branch removed" git -C "$MPROJECT" rev-parse --verify -q change/feat-merge.a
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
check_err "merge: out-of-scope file named and refused" "b.js" $RC unit merge --store teststore --project "$MPROJECT" --name feat-scope --unit a
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
check_err "merge: dep not merged refused" "not merged" $RC unit merge --store teststore --project "$MPROJECT" --name feat-mdep --unit b
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

finish
