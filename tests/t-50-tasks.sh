#!/usr/bin/env bash
# tasks open: unchecked tasks.md lines, worktree copy precedence.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
teststore
mkorigin
register_store localstore "$PROJECT"

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
check_err "tasks open errors when no change directory exists anywhere" "no change directory found" $RC tasks open --store teststore --name feat-notasks
check_out "tasks open writes nothing when no change directory exists" 'manual_tasks_open: ""' $RC state get --store teststore --name feat-notasks

# change directory exists but has no tasks.md (e.g. a triage bugfix)
mkdir -p "$STORE/openspec/changes/feat-notasksmd"
$RC state init --store teststore --name feat-notasksmd
check_out "tasks open without tasks.md reports it" "no tasks.md for feat-notasksmd" $RC tasks open --store teststore --name feat-notasksmd
check_out "tasks open without tasks.md records 0" "manual_tasks_open: 0" $RC state get --store teststore --name feat-notasksmd

finish
