# parallel-units Specification

## Purpose
TBD - created by archiving change parallel-unit-execution. Update Purpose after archive.

## Requirements

### Requirement: Unit split recorded in state
At phase `applying` with an empty `units` field, `next` SHALL return `action: split` — tier `deep` under `lifecycle: full` with parallel mode on, tier `none` with a reason naming `units single` otherwise — and SHALL NOT print a `running:` line. The split SHALL be recorded only as state fields: `units` (`<u>=<file>,<file>;...`, the seam dialect), `unit_deps` (`<u>=<dep>,<dep>;...`), `unit_tasks` (`<u>=<task-id>,...;...`), `ui_units` (`<u>,<u>`). `state init` SHALL write all four and `parallel` as `""`. The state-only check `units_check` SHALL fail when a unit name is not kebab-case, a dep names no unit, deps form a cycle, a unit file is in no `seams` list, two units with overlapping files are not ordered by a dep path, a unit has no file, or a task id is in two units. `next` SHALL run only that check (it reads no tasks.md and no worktree) and exit non-zero when it fails. `scripts/run-change units check --store <slug> --name <change>` SHALL run the same check, then print `unassigned: <id>` for each tasks.md id in no unit, and exit 0 when the check passes. `units single [--ui]` SHALL write one unit `all` holding the union of the seam files and every task id, with `ui_units: all` under `--ui`.

#### Scenario: Full parallel split at deep
- **WHEN** a `full` change is at `applying` with `units: ""`
- **THEN** `next` returns `action: split` and `tier: deep`, with no `running:` line

#### Scenario: Cycle rejected
- **WHEN** `unit_deps: "a=b;b=a"`
- **THEN** `units check` exits non-zero naming `a` and `b`, and `next` exits non-zero

#### Scenario: Unordered overlap rejected
- **WHEN** `units: "a=x.js;b=x.js"` and `unit_deps: ""`
- **THEN** `units check` exits non-zero; with `unit_deps: "b=a"` it exits 0

#### Scenario: File outside the seams
- **WHEN** a unit lists a file no `seams` group names
- **THEN** `units check` exits non-zero naming the file

#### Scenario: Unassigned task printed by the CLI only
- **WHEN** tasks.md has ids 1.1 and 1.2 and `unit_tasks: "a=1.1"`
- **THEN** `units check` prints `unassigned: 1.2` and exits 0, and `next` succeeds even when the change has no tasks.md

#### Scenario: Single unit
- **WHEN** `seams: "s1=a.js;s2=b.js"` and `units single --ui` runs
- **THEN** `units` is `all=a.js,b.js` and `ui_units` is `all`

### Requirement: Per-unit worktree and branch lifecycle
`workspace_path <slug> <name> <unit>` SHALL return `<store>/.orchestration/workspaces/<name>.<unit>` and remain the only builder of workspace paths; the unit branch SHALL be `change/<name>.<unit>`. `unit create --store --project --name --unit` SHALL refuse an unknown unit, a unit whose file exists with a status other than `pending`, a unit with a dep not `merged`, or a change worktree with uncommitted changes; otherwise it SHALL create the branch off the tip of `change/<name>`, check it out at the unit path, and write `<store>/.orchestration/state/<name>.units/<unit>.yaml` with `status: running`, `iterations: 0`, `base: <sha of change/<name>>`; it SHALL take no tier option (unit writers run at `standard`). `unit remove` SHALL remove that worktree and delete that branch. `workspace remove` SHALL also remove every unit worktree and branch of the change. `gate run --unit <u>` SHALL run the gate in the unit worktree and SHALL NOT write `gate_tree`. A unit worker SHALL commit only on its unit branch, only its unit's files, and SHALL NOT push, rebase, merge, checkout, or write any other branch; every other worker except the merge-conflict agent SHALL run no git write. On `apply`, and before acting on `split` for a change resumed at `applying`, the orchestrator SHALL commit any uncommitted work in the change worktree.

#### Scenario: Create and remove
- **WHEN** `unit create --unit a` runs for a change with `units: "a=x.js"`
- **THEN** `git worktree list` shows `<store>/.orchestration/workspaces/<name>.a` on `change/<name>.a`, the unit file has `status: running` and `base` equal to `git rev-parse change/<name>`; after `unit remove --unit a` neither the worktree nor the branch exists

#### Scenario: Dep not merged
- **WHEN** `unit_deps: "b=a"` and unit `a` is `running`
- **THEN** `unit create --unit b` exits non-zero and creates no branch

#### Scenario: Dirty change worktree
- **WHEN** the change worktree has an uncommitted file
- **THEN** `unit create` exits non-zero naming the change worktree and creates no branch

#### Scenario: Workspace remove cleans units
- **WHEN** a change has a unit worktree and `workspace remove` runs
- **THEN** no `change/<name>.*` branch and no `<name>.*` worktree remains

#### Scenario: Unit gate leaves gate_tree alone
- **WHEN** `gate run --unit a --mode full` passes
- **THEN** the output shows the unit worktree path and the change's `gate_tree` is unchanged

### Requirement: Scheduler
A unit with status `running`, `reviewing`, `conflict`, or `resolving` SHALL hold a slot. Capacity SHALL be `orchestration.unit_concurrency`, else `orchestration.concurrency`, else 1. `units next --store --name` SHALL print `ready:` with the units that have no unit file or `status: pending` and whose deps are all `merged`, in `units` field order, at most capacity minus slot holders; `running:` with the slot holders; and `capacity:` with the free capacity. `unit-revise` and `merge-conflict` SHALL reuse the slot their unit holds. `units list` SHALL print `<u> <status> <iterations>` per unit in field order. `status` SHALL show a `UNITS` column `<merged>/<total>`, `-` for a change with no units.

#### Scenario: Capacity and order
- **WHEN** `units: "c=c.js;a=a.js;b=b.js"`, no deps, unit capacity 2, none created
- **THEN** `units next` prints `ready: c a`

#### Scenario: Running units consume capacity
- **WHEN** unit capacity is 2 and `c` is `running`
- **THEN** `units next` prints `ready: a` and `running: c`

#### Scenario: Units under review hold their slot
- **WHEN** unit capacity is 2, `a` is `reviewing`, `b` is `running`, `c` is pending
- **THEN** `units next` prints an empty `ready:` and `capacity: 0`

#### Scenario: Dep gating
- **WHEN** `unit_deps: "b=a"` and `a` is `reviewed`
- **THEN** `b` is not in `ready:`; once `a` is `merged`, it is

#### Scenario: unit_concurrency overrides concurrency
- **WHEN** the store sets `concurrency: 2` and `unit_concurrency: 3` and three independent units are pending
- **THEN** `units next` lists all three

### Requirement: Check-first worker contract
`unit checks-done --unit <u>` SHALL record `checks_commit` as the unit branch HEAD and SHALL refuse while HEAD equals `base`. `unit iterate` SHALL refuse while `checks_commit` is empty. AUTONOMOUS-ORCHESTRATION.md **Unit workers** SHALL state: checks are written and committed before implementation and are part of what `gate_quick` runs; for a unit in `ui_units`, a Playwright script launches the page at 1280×800, saves a screenshot to `$UNIT_SCREENSHOT` only when `$UNIT_NAME` equals the unit that owns the test (other units' UI tests still run and assert but write nothing), and asserts the board/canvas bounding box lies inside the viewport, no horizontal overflow, every SVG shape has non-`none` fill or stroke, every DOM-grid cell has a non-transparent background, and one assertion per requirement the unit implements; `playwright` is the only dependency a worker may add, as a target-project devDependency listed in the unit's files and shown in the Gate 2 diffstat; the engine never depends on it; the worker never reports its own check result.

#### Scenario: Iterate before checks refused
- **WHEN** a unit was just created and `unit iterate` runs
- **THEN** it exits non-zero, runs no gate, and the session log gains no entry

#### Scenario: Checks-done needs a commit
- **WHEN** the unit branch HEAD equals `base`
- **THEN** `unit checks-done` exits non-zero; after a commit it records that sha as `checks_commit`

#### Scenario: Doc states the contract
- **WHEN** a reader checks AUTONOMOUS-ORCHESTRATION.md **Unit workers**
- **THEN** it names `checks-done`, `UNIT_SCREENSHOT`, `UNIT_NAME`, the four layout invariants, and the Playwright devDependency rule

### Requirement: Engine-run iterations with a cap and session logging
`unit iterate --store --project --name --unit <u>` SHALL, with n = iterations + 1 ≤ `UNIT_ITER_CAP` (5), run `orchestration.gate_quick` in the unit worktree with `UNIT_SCREENSHOT` exported as the absolute path `<store>/.orchestration/state/<name>.units/<u>/screenshot-<n>.png` (directory created) and `UNIT_NAME=<u>`, and take the result from the gate's exit code: `green` on 0, else `red`; for a unit in `ui_units` the result SHALL be `red` when that PNG does not exist afterwards. It SHALL then append `role=worker phase=unit unit=<u> event=iterate iteration=<n> checks=<result> tier=standard model=<standard model>` to the change's session log, write `iterations: n`, write `screenshot: <absolute path>` when the PNG exists, set `status: green` on green and `status: failed` on red at n = 5, and exit 0 on green, 1 on red. It SHALL accept no result argument. n > 5 SHALL run no gate, append nothing, set `status: failed`, and exit non-zero. `next` SHALL return `gate1` naming the unit while any unit is `failed`. Other unit session entries SHALL have the shapes `role worker phase unit unit <u> event spawn tier standard model <m> transcript_id <id>`, `role critic phase unit unit <u> event critique iteration <n> tier <t> model <m> transcript_id <id>`, `role worker phase unit unit <u> event merge-conflict tier standard model <m> transcript_id <id>`, `role orchestrator phase unit unit <u> event merge result <merged|conflict|failed>` (appended by `unit merge` on every rebase attempt; refusals log nothing), and `role orchestrator phase unit event units-merged`, as stated in AUTONOMOUS-ORCHESTRATION.md.

#### Scenario: Result comes from the gate
- **WHEN** the store's `gate_quick` exits 1 unless a file `OK` exists in its working directory, and `unit iterate` runs four times before the worker creates `OK` and once after
- **THEN** the session log has 5 `phase=unit unit=<u> event=iterate` entries `iteration=1` to `iteration=5`, the first four `checks=red`, the last `checks=green`, and status is `green`

#### Scenario: Sixth refused
- **WHEN** a unit has `iterations: 5` and `unit iterate` runs
- **THEN** it exits non-zero, the gate does not run, the log gains no entry, status is `failed`, and `next` returns `action: gate1`

#### Scenario: UI green needs the screenshot
- **WHEN** a unit in `ui_units` runs `unit iterate` with a `gate_quick` that exits 0 but writes nothing to `$UNIT_SCREENSHOT`
- **THEN** the entry has `checks=red` and status is not `green`; with a `gate_quick` that writes `$UNIT_SCREENSHOT` it is `green` and `screenshot` holds that absolute path

#### Scenario: Only the owning unit's test writes the screenshot
- **WHEN** `gate_quick` exits 0 and writes `$UNIT_SCREENSHOT` only when `UNIT_NAME` is `a`, and UI unit `b` runs `unit iterate`
- **THEN** `b`'s entry has `checks=red` and no `screenshot` is recorded for `b`; for UI unit `a` the entry has `checks=green`

### Requirement: Critic over green units with screenshots
`units ready-for-review` SHALL print `unit: <u>` followed by `screenshot: <absolute path>` for each PNG of that unit, for every unit with `status: green` and empty `critique`. At `applying`, `next` SHALL return `unit-critique` with the tier and model `model critic` resolves and a `units:` line, when such a unit exists and no unit is `failed` or `conflict`, no `reviewing` unit has a blocking critique, and no reviewed unit is mergeable. `unit set --unit <u> critique <result>` for a unit in `ui_units` SHALL refuse unless `<name>.units/<u>.critique.md` exists and contains the unit's `screenshot` value as a fixed string. A unit with `status: reviewing` and `critique: blocking:<n>` SHALL yield `unit-revise` (tier `standard`) when iterations < 5, else `gate1`.

#### Scenario: Only green units reviewed
- **WHEN** units `a` is `green`, `b` is `running`
- **THEN** `units ready-for-review` lists `a` only, and `next` returns `action: unit-critique` with `units: a` and `running: b`

#### Scenario: Critic tier
- **WHEN** the proposer's last `proposed` entry is `tier deep`
- **THEN** the `unit-critique` output has `tier: max`

#### Scenario: Critique must cite the recorded screenshot
- **WHEN** a UI unit's `screenshot` is `<abs>/screenshot-1.png` and its critique report contains only the basename `screenshot-1.png`
- **THEN** `unit set critique clean` exits non-zero; with the absolute path in the report it exits 0

#### Scenario: Blocking within the cap
- **WHEN** a unit is `reviewing`, `critique: blocking:1`, `iterations: 2`
- **THEN** `next` returns `action: unit-revise`; with `iterations: 5` it returns `action: gate1`

### Requirement: Merger order and conflict handling
`units merge-order` SHALL print units in a topological order of `unit_deps`, ties broken by `units` field order, and exit non-zero on a cycle. `unit merge --store --project --name --unit` SHALL refuse a unit not `reviewed`/`resolving`, a dep not `merged`, or a branch diff touching a file outside the unit's list; otherwise it SHALL rebase the unit branch onto `change/<name>`, fast-forward `change/<name>`, tick the unit's `unit_tasks` in the change's tasks.md, remove the unit worktree and branch, and set `status: merged`. From `resolving` with a rebase still in progress in the unit worktree, it SHALL abort that rebase and set `status: failed` (regardless of `merge_attempts`), exit 3. On a rebase conflict it SHALL abort the rebase, print the conflicting files, increment `merge_attempts`, set `status: conflict` (or `failed` when `merge_attempts` was already 1), and exit 3. Every rebase attempt SHALL append an `event merge` session entry; refusals log nothing. `next` SHALL return `unit-merge` (tier none, `units:` in merge order) for reviewed units whose deps are merged, `merge-conflict` (tier `standard`) for a `conflict` unit, and `units-merged` with `set_phase: checking` once every unit is `merged`; the existing `checking` path then runs `gate_full` and Verify on the change branch, and Archive, merge lane, Gate 2 and squash-merge are unchanged.

#### Scenario: Merge order
- **WHEN** `units: "c=c.js;b=b.js;a=a.js"`, `unit_deps: "c=a;b=a"`
- **THEN** `units merge-order` prints `a c b`

#### Scenario: Fast-forward
- **WHEN** reviewed unit `a` has one commit and `unit merge --unit a` runs
- **THEN** `change/<name>` contains that commit, task ids of `a` are `- [x]` in tasks.md, the unit worktree and branch are gone, and status is `merged`

#### Scenario: Out-of-scope file refused
- **WHEN** unit `a` (files `a.js`) committed `b.js`
- **THEN** `unit merge --unit a` exits non-zero naming `b.js` and `change/<name>` is unchanged

#### Scenario: Conflict then failure
- **WHEN** a rebase conflicts
- **THEN** `unit merge` exits 3 printing the file, status is `conflict`, `next` returns `action: merge-conflict`; a second conflict sets `status: failed` and `next` returns `action: gate1`

#### Scenario: Unfinished conflict resolution
- **WHEN** a unit is `resolving` and its worktree still has a rebase in progress
- **THEN** `unit merge` aborts it, exits 3, sets `status: failed` (regardless of `merge_attempts`), and the session log gains an `event=merge result=failed` entry

#### Scenario: All merged
- **WHEN** every unit is `merged`
- **THEN** `next` returns `action: units-merged` and `set_phase: checking`

### Requirement: Scheduling actions
`awaiting-acceptance` with `acceptance: accepted` SHALL return `action: apply`, `tier: none`, `model: -`, `set_phase: applying`, with a reason saying to commit any uncommitted work in the change worktree and that the split follows; no worker is dispatched on it. At `applying` with units recorded, `next` SHALL return `unit-spawn` (tier `standard`, `units:` = `units next` ready list) when units are ready and no higher row applies, and `wait` when units are only `running`, `reviewing`, or `resolving`. The orchestrator SHALL set `status reviewing` before dispatching a unit critic and `status resolving` before dispatching a merge-conflict agent, so a repeated `next` does not dispatch the same work twice. Every output at `applying` other than `split` SHALL include a `running:` line listing the slot holders (empty when there are none).

#### Scenario: Apply is bookkeeping
- **WHEN** a change at `awaiting-acceptance` has `acceptance: accepted`
- **THEN** `next` returns `action: apply`, `tier: none`, `model: -`, `set_phase: applying`

#### Scenario: Spawn
- **WHEN** a change at `applying` has `units: "a=a.js;b=b.js"` and no unit files
- **THEN** `next` returns `action: unit-spawn`, `tier: standard`, `units: a b`, and a `running:` line

#### Scenario: Wait
- **WHEN** both units are `running` and capacity is 2
- **THEN** `next` returns `action: wait` with `running: a b`

### Requirement: Single-worker baseline mode
The `parallel` field SHALL read, when empty, the store's `orchestration.parallel`, and when that is unset, `true`; a value other than `true`/`false` SHALL make `next` exit non-zero. With `parallel: false`, `split` SHALL be tier `none` with a reason naming `units single`, so the change runs one unit serially.

#### Scenario: Baseline split
- **WHEN** a `full` change at `applying` has `parallel: false` and empty `units`
- **THEN** `next` returns `action: split`, `tier: none`, reason containing `units single`

#### Scenario: Store default
- **WHEN** the store sets `orchestration.parallel: false` and the change's `parallel` is empty
- **THEN** `next` returns `split` at `tier: none`

#### Scenario: Bad value
- **WHEN** `parallel: maybe`
- **THEN** `next` exits non-zero
