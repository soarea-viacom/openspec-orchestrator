#!/usr/bin/env bash
# Project-side behaviour: openspec/ refusal, local mode, merge lane, repo init, trunk preflight, gate timeout.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
teststore
mkorigin
# feat-a: a change whose full gate already passed on the current trunk tree
mkchange teststore feat-a
$RC workspace create --store teststore --project "$PROJECT" --name feat-a >/dev/null
$RC gate run --store teststore --project "$PROJECT" --name feat-a --mode full >/dev/null

# a project with its own openspec/ folder is refused when the resolved
# store is a DIFFERENT external root (that combination means the caller
# picked the wrong store for a project that should run in local mode)
mkdir "$PROJECT/openspec"
check_err "slot acquire refuses project with openspec/ against a different store" "refusing" $RC slot acquire --store teststore --project "$PROJECT"
check_err "workspace create refuses project with openspec/ against a different store" "refusing" $RC workspace create --store teststore --project "$PROJECT" --name feat-x
check_err "gate run refuses project with openspec/ against a different store" "refusing" $RC gate run --store teststore --project "$PROJECT" --name feat-x --mode quick
check_err "merge lane refuses project with openspec/ against a different store" "refusing" $RC merge-lane run --store teststore --project "$PROJECT" --name feat-x

# local mode: a store whose local_path IS the project itself is not refused,
# even though the project has its own openspec/ folder (SKILL.md Step 1)
register_store localstore "$PROJECT"
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
check_out "merge lane skips the gate when the tree already passed it" "skipping rerun" $RC merge-lane run --store teststore --project "$PROJECT" --name feat-a
echo moved > "$PROJECT/TRUNK-MOVED" && git -C "$PROJECT" add -A && git -C "$PROJECT" commit -qm trunk-moves && git -C "$PROJECT" push -q origin main
before="$(grep '^gate_tree:' "$STORE/.orchestration/state/feat-a.yaml")"
check_out "merge lane merges trunk and reruns full gate when the tree changed" "FULL-OK in $STORE/.orchestration/workspaces/feat-a" $RC merge-lane run --store teststore --project "$PROJECT" --name feat-a
check "rerun full gate records the new tree" test "$(grep '^gate_tree:' "$STORE/.orchestration/state/feat-a.yaml")" != "$before"

# merge lane on a local-only project (no remote): merges the local trunk
LOCAL="$TMP/local-project"
mkproject "$LOCAL"
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
check_err "merge lane errors when no trunk is identifiable" "cannot determine trunk" $RC merge-lane run --store teststore --project "$NOTRUNK" --name feat-nt
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
mkstore teststore2 "$TMP/store2" >/dev/null <<'EOF'
orchestration:
  concurrency: 1
  gate_quick: "echo QUICK-OK in $PWD"
  gate_full: "exit 1"
EOF
check_err "gate run --trunk red names the trunk as red" "is red" $RC gate run --store teststore2 --project "$PROJECT" --mode full --trunk
check_fails "gate run --trunk red exits non-zero" $RC gate run --store teststore2 --project "$PROJECT" --mode full --trunk
check "gate run --trunk red leaves no trunk-preflight worktree behind" bash -c "! git -C '$PROJECT' worktree list | grep -q trunk-preflight"

# gate_timeout: a gate blocked on stdin, with a spawned child, is killed as a group
mkstore teststore3 "$TMP/store3" >/dev/null <<'EOF'
orchestration:
  concurrency: 1
  gate_timeout: 2
  gate_full: "sleep 31337 & cat; wait"
EOF
t0=$SECONDS
to_rc=0; to_out="$($RC gate run --store teststore3 --project "$PROJECT" --mode full --trunk 2>&1)" || to_rc=$?
check "gate run timeout returns within the limit, not when stdin closes" test $((SECONDS - t0)) -lt 15
check "gate run timeout exits 124" test "$to_rc" -eq 124
check_out "gate run names a timed-out gate" "gate timed out after 2s" printf '%s\n' "$to_out"
check_fails "gate run timeout kills the gate's children" pgrep -f 'sleep [3]1337'

finish
