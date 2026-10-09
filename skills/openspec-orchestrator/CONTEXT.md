# Domain glossary

- **Store**: a directory holding OpenSpec artifacts and orchestration state
  for one target project, resolved by slug via the CLI registry
  (`OPENSPEC_STORE_REGISTRY`).
- **Change**: the unit of branch, workspace, gate and merge
  (`change/<name>` branch in the target project's repo, worktree checked
  out at `<store>/.orchestration/workspaces/<name>` — `workspace_path` in
  `scripts/lib.sh` is the only place that path is built, and also builds
  each unit's own worktree at `<name>.<unit>` off its own branch
  `change/<name>.<unit>`). Gates run in a worktree — the change's own, or
  `--unit <u>`'s — never the project's main checkout.
- **State module**: `scripts/lib.sh` (`state_root`, `state_field`,
  `state_write`) — sole owner of the state-file YAML dialect under
  `<store>/.orchestration/state/`. Nothing else parses those files. All
  upserts from the CLI — change state and initiative records alike — go
  through one helper, `set_record` in `scripts/run-change`, which is also
  where the `prev_*_result` shift lives.
- **Worker**: one agent dispatched by the orchestrator into its own context
  window for one task — a unit worker, a fixer, a critic, a Verify
  checker, a triage read. Receives only what the orchestrator hands it plus
  what it reads from disk; never another agent's transcript. A unit worker
  is the one writer that does run git writes, confined to its own unit
  worktree and branch (see **Unit**); every other writer stays inside its
  file list and never runs a git command that writes. Read-only workers
  are exempt from the disjoint-files check.
- **Advisor**: a read-only `deep`-tier subagent a stuck `standard` or
  `mechanical` worker asks one packaged question, fresh context, answer
  only. Obtained only via `scripts/run-change advisor request --worker
  <transcript-id>`, which enforces the caps (one per worker task, two per
  change — `ADVISOR_CAP` in `scripts/lib.sh`) and writes the `role advisor
  tier deep for=<worker>` session entry itself; `session append` refuses
  that role. Never from `deep` and never from a checker. Required, not
  optional, for a unit worker at its second consecutive red
  (`REDS_BEFORE_ADVISOR`): `unit iterate` refuses to run again until
  `advisor request --unit <u>` has been granted, and a red after the
  answer fails the unit with `fail_reason red-after-advice` straight to
  Gate 1. Distinct from tier escalation, which re-runs the
  whole task at the higher tier.
- **Blackboard**: the orchestrator-owned files agents share through —
  proposal, seam list, state, reports. The only channel between agents;
  there is no worker-to-worker messaging.
- **Unit**: the unit of concurrent implementation within a change — one
  independent slice of the seam list and tasks.md, recorded in state
  (`units`, `unit_deps`, `unit_tasks`, `ui_units`, the seam dialect for the
  first three) and given its own worktree (`<ws>/<name>.<unit>`) and
  branch (`change/<name>.<unit>`, `unit_branch` in `scripts/lib.sh`). A
  unit worker is the sole writer there and the only kind of worker that
  commits; the merger (below) integrates a reviewed unit onto
  `change/<name>` once its deps have. `split` (tier `deep` under the full
  parallel path, else `units single` at `none`) writes the four fields and
  runs `units_check`.
- **Unit size cap**: `UNIT_MAX_FILES` (8) and `UNIT_MAX_TASKS` (3), store
  overrides `orchestration.unit_max_files` / `unit_max_tasks`; `units
  check` refuses a unit over either unless the change's `unit_size_ok`
  field names it (then it warns). Set only with a justification in the
  proposal.
- **Unit state file**: `<store>/.orchestration/state/<name>.units/<unit>.yaml`
  — one file per unit, not a field on the change file, because concurrent
  unit workers calling `unit iterate` would otherwise race a shared
  read-modify-write. Fields: `status` (`pending` → `running` → `green` →
  `reviewing` → `reviewed` → `merged`, or `failed`, or `conflict` →
  `resolving`), `iterations`, `base` (the sha the unit branched from),
  `checks_commit`, `screenshot` (absolute path of the latest green
  iteration's PNG), `critique`, `merge_attempts`, `reds_in_row`
  (consecutive red iterations, reset by a green), `advised` (the
  iteration count when `advisor request --unit` was granted), and
  `fail_reason` (`spec` | `iteration-cap` | `red-after-advice` |
  `merge-conflict`; `unit set` refuses other values) which `next` reads to
  word the `gate1` it returns for a `failed` unit. Written through `unit
  set`/`unit get --unit <u>`, same `set_record` machinery as the change
  file.
- **Scheduler**: `units next` — the units whose deps are all `merged` and
  have no unit file or `status: pending`, in `units` field order, up to the free capacity
  (`orchestration.unit_concurrency`, default 3; the change-level
  `concurrency` defaults to 2). A unit with status `running`, `reviewing`, `conflict`, or
  `resolving` holds a slot — review and conflict resolution reuse the slot
  the unit already holds rather than freeing it for a new unit to start.
- **Unit critique**: the critic dispatched over `units ready-for-review`
  (every `green` unit with no `critique` recorded yet), one tier above
  that unit's own worker — `deep` over a `standard` leaf, `max` over a
  `deep` foundation unit (two or more units depend on it directly; `unit
  create` records the tier on the unit's state file). Its
  report, `<name>.units/<unit>.critique.md`, must quote the unit's
  recorded `screenshot` path verbatim for a unit in `ui_units`; `unit set
  critique` refuses otherwise. `blocking` sends the unit back to
  `unit-revise` within its own iteration cap; there is no separate
  critique-round counter (see **Checker loops** in
  AUTONOMOUS-ORCHESTRATION.md).
- **Unit merge**: `units merge-order` (topological over `unit_deps`, ties
  by `units` field order) then `unit merge --unit <u>`, tier `none`:
  rebase the unit branch onto `change/<name>`, fast-forward, tick the
  unit's `unit_tasks` in tasks.md, remove the unit worktree and branch. A
  rebase conflict dispatches a `standard` merge-conflict agent confined to
  the files it named; a second conflict, or an unfinished `resolving`
  rebase, fails the unit to **Gate 1**. Every rebase attempt — success or
  conflict — appends an `event merge` session entry; a refusal (wrong
  status, unmerged dep, out-of-scope diff) logs nothing.
- **Parallel mode**: the `parallel` state field — `true` (default, empty
  reads the store's `orchestration.parallel`, else `true`) or `false`.
  `false` makes `split` run `units single` at tier `none`, so the change's
  tasks run as one unit instead of fanning out, for comparing a parallel
  run against a single-worker baseline from the same trunk commit.
- **Slot**: a concurrency token under `<store>/.orchestration/slots/`,
  capped by `orchestration.concurrency` in the store's config.
- **Seam list**: the `seams` field in a change's state file, written during
  Propose via `scripts/run-change state set --store <slug> --name <change>
  seams "<seam>=<file>,<file>;<seam>=<file>"` — one `name=file,file,...`
  group per seam, groups separated by `;`. The sole source the
  disjoint-files check reads from; nothing infers seams from the delta spec
  prose or from the code after the fact.
- **Session log**: `<store>/.orchestration/state/<change>.sessions.log` —
  an append-only, one-line-per-run history, written via `scripts/run-change
  session append --store <slug> --name <change> key value [key value ...]`
  and read via `session list`. Distinct from the per-change state file: the
  state file holds the *current* record for a change (one value per key,
  upserted in place); the session log holds *every* run's record (`role`,
  `phase`, `gates_hit`, `transcript_id`, `model`, `tier`), appended, never
  rewritten.
- **Tier→model table**: the mapping from an effort tier (`mechanical`,
  `standard`, `deep` — the `none` tier runs no model) to a concrete model
  id, read via `scripts/run-change model get --store <slug> --tier
  <tier>`. Resolved from the store's `openspec/config.yaml`
  (`orchestration.model_<tier>`, `model_<tier>_fallback`) if set, else
  `models.tsv` for the store's `orchestration.tool` — the only place model
  ids are named. Two models per tier (default, fallback); newest version per
  family wins.
- **Generator/checker split**: the rule that a checker runs one tier
  above the generator whose output it judges — `mechanical < standard <
  deep < max` — dropping to the tier below only when the generator is
  already at `max`. Two instances: Verify's checker vs. the implementer
  (`implementer_tier`/`implementer_model` read the last
  `applying`/`checking` session entry) and Propose's critic vs. the
  proposer (`proposer_tier`/`proposer_model` read the last `proposed`
  entry). Both go through `checker_pick` (`scripts/lib.sh`), which errors
  if the chosen tier resolves to the generator's own model id. Exposed as
  `scripts/run-change model verify|critic --store <slug> --name <change>`.
- **Tier ladder**: `mechanical`, `standard`, `deep`, `max`, weakest first
  (`TIERS` in `scripts/lib.sh`). `max` is reached only as a checker tier.
- **Critique report**: `<store>/.orchestration/state/<change>.critique.md`,
  written by the Propose critic, overwritten each round. Each finding
  names the spec section or seam, the defect, and what would satisfy it.
  Summarized in `last_critique_result` as `clean`, `warnings:<m>`,
  `blocking:<n>`, or `request`; only `blocking` starts a round. Rounds counted in `propose_rounds`, cap 2, independent of
  `fix_attempts`.
- **Verify floor**: Verify runs at the highest of three tiers — one above
  the last implementer, the previous Verify round's tier on this change,
  and `deep` (`VERIFY_FLOOR`). `model verify` and `next` name the floor
  when it, not the tier-above rule, decided. Verify only; the critic and
  unit critic are unaffected.
- **Verify report**: `<store>/.orchestration/state/<change>.verify.md`,
  written by the Verify checker and overwritten each round (current
  record, like the state file). Each finding carries the proposal
  requirement, `file:line`, the defect, and what would satisfy it.
  Summarized in the state field `last_verify_result` as `clean`,
  `warnings:<m>`, `blocking:<n>`, or `spec`; only `blocking` starts a
  fix round. The sole input a fix round receives from
  Verify — the fixer never sees the checker's transcript.
- **Fix round**: one bounded correction pass, triggered by either a red
  full gate or a `blocking` verify report. Both draw on the same
  `fix_attempts` counter, capped at 3 per change; tier escalates by round
  number, then Gate 1.
- **Convergence test**: a checker round converges only if no finding the
  prior report marked closed reappears and the blocking count strictly
  falls. A round that fails it gates to the human immediately, ignoring
  remaining budget. Applies to fix rounds and critique rounds alike (see
  **Checker loops** in AUTONOMOUS-ORCHESTRATION.md). The count half is
  enforced by `next` from `prev_verify_result` / `prev_critique_result`,
  which `state set` shifts automatically whenever a real result is
  overwritten (including by the clear before a recheck); the
  reopened-finding half remains the checker's judgement.
- **Pass line**: Verify passes on full gate green plus zero `blocking`
  findings; critique passes on zero `blocking` findings. `warning`
  findings get one mechanical sweep and never start a round.
- **Next action**: `scripts/run-change next --store <slug> --name <change>`
  — the orchestration policy as one read-only function (`next_action` in
  `scripts/lib.sh`) that maps a change's state file + session log to the
  single next step (`action`, `tier`, `model`, `set_phase`, `reason`,
  `prompt` for a role-bearing action; on `check` also `also: verify` +
  `also_model` + `also_prompt`, a read-only step to run concurrently). The
  agent does the step and records results; it never re-derives the
  lifecycle from prose. Caps live beside it: `FIX_CAP`, `PROPOSE_CAP`,
  `ADVISOR_CAP`. Its action set includes `tasks-open` (records the
  manual-task count and `set_phase: verified`, the step that must run
  before `archive` is ever returned) and `gate2-manual` (the manual-task
  block at `verified` — see **Manual tasks** above).
- **Gate**: the project's quick or full check command
  (`orchestration.gate_quick` / `gate_ui` / `gate_full` in the *store's*
  `openspec/config.yaml` — single rule: a target project must not contain
  an `openspec/` folder; the engine refuses one that does). `gate_quick`
  should stay under ~30 s — it runs on every unit iteration; `gate_ui`
  (browser tests) runs after it for units in `ui_units` only; anything
  slower belongs in `gate_full`, which runs once per Check. The full gate
  includes the project's dead-code pass (`knip`, `vulture`, or
  equivalent); for this engine that is the no-caller function scan in
  `tests/run.sh`.
- **Trunk preflight**: `scripts/run-change gate run --store <slug>
  --project <path> --mode full --trunk` — runs `gate_full` in a temporary
  detached worktree of the trunk ref, writes no state, and removes the
  worktree whether the gate passes or fails. Runs before `slot acquire`
  and `workspace create` (SKILL.md Step 0 check 4); red, or `gate_full`
  unconfigured, stops the flow and opens no change.
- **Lifecycle**: the state field `lifecycle`, `full` or `light` (empty
  reads as `full`; any other value errors). Under `light`, Propose and
  `revise` run at `standard` instead of `deep` (the critic still resolves
  one tier above, to `deep`); `split` runs `units single`, so the change is
  exactly one unit; a green gate with `warnings:<m>` skips the mechanical
  sweep instead of running it; a non-UI `standard` leaf green on iteration
  1 takes `unit-pass` (`unit pass`, critique `skipped`, logged as
  `critique-skipped`) instead of a unit critic. Everything else, including
  Gate 0 and the proposal critic, is unchanged. Set only by triage on the bugfix change it opens, or by the
  human through Gate 0's "Accept — light lifecycle" option — never by the
  orchestrator for any other change.
- **Manual tasks**: `scripts/run-change tasks open --store <slug> --name
  <change>` prints the change's unchecked `- [ ]` task lines and records
  their count as the state field `manual_tasks_open` (an explicit `0` when
  none are open, `""` when never counted). At phase `verified`, a count
  greater than 0 with `manual_accept` empty blocks archive with action
  `gate2-manual`; the human ticks tasks (the orchestrator edits tasks.md
  and reruns `tasks open`) or records `manual_accept:
  accepted:<requirement>[;<requirement>...]` naming the requirements left
  unverified. `openspec archive --yes` runs only when the recorded count
  is `0` or `manual_accept` is set, never otherwise.
- **Checker input contract**: the fixed set of inputs `model critic` and
  `model verify` print as `input:` lines after the bare model id — critic:
  request, draft, seam list, Project glossary, ADRs, prior report; Verify:
  proposal, seam list, branch diff, the store's `config.yaml` (a new
  `orchestration.*` key, role overlay, or convention not reflected there is
  one warning), prior report. Both read no state file to produce this; the
  seam-list line names the field rather than resolving it. Other files are
  read only to confirm a seam is real or a dependency claim true, never to
  explore the codebase at large.
- **Classification**: the four pillar readings — scope, blast radius,
  novelty, dependency impact — recorded by the `classify` step (tier
  `standard`) in the state field `pillars` as
  `scope=file|seam|seams;blast=none|project|public;novelty=known|new;deps=none|dev|runtime`
  (`next` refuses other values), repeated in the proposal and shown in
  the Gate 0 resume. Trivial — scope `file` or `seam`, the other three at
  their first value — → fast-path fix, grill skipped, Gate 0 offers
  `light`; blast radius or dependency impact beyond the project, or
  independently-mergeable parts → initiative; else a `full` change that
  goes through grill first. The critic grades the readings under Right
  size; a pillar read low to earn the fast path is `blocking`.
- **Grill (state field)**: `""`, `done`, or `skipped:human`. `next`
  returns `grill` for a classified, non-trivial change until it is `done`
  or `skipped:human`; only the human records the skip.
- **Guardrails**: the proposal line naming what the change must not
  introduce (dependency, abstraction, public signature, widened seam).
  The critic checks it names real risks for the seam; Verify grades the
  diff against it as against any requirement. It never excludes the
  implied baseline.
- **Implied baseline**: what a request means without saying — physical
  law and nature for anything simulated, the domain's conventions,
  programming best practice — selected by the request's **register**:
  "realistic" or silence → natural law; a genre word ("fantastic", "SF",
  "fairy-tale") → that genre's rules. Part of the request: the proposer
  writes it into the requirements, grill never asks it, the critic blocks
  a draft missing part of it, Verify grades it like any requirement.
- **Project glossary**: `<root>/openspec/CONTEXT.md`, plus ADRs in
  `<root>/openspec/adr/` — the canonical terms and decisions a grill-mode
  interview records for one project. Distinct from this engine's own
  glossary (this file); written only by grill mode, read by the proposer
  and the critic.
- **Grill mode**: the interview that settles what and how (SKILL.md
  **Grill mode**), with two entries: standalone before any change, or
  in-change when `next` returns `grill` after `classify`. First
  round analyses the request (two or three approaches, no writes);
  the interview then runs `grilling` and `domain-modeling` to sharpen
  terms and decisions into the Project glossary and ADRs; an external-mode
  guard compares `git status --porcelain` before and after; nothing is
  ever committed.
- **Role agent**: the agent definition for a role,
  `openspec-<role>` (`agents/openspec-<role>/AGENT.md` here, installed by
  Atlas), body = the role prompt verbatim, frontmatter = effort (`high`
  proposer/critic/verifier, `medium` unit-critic/worker) and tool
  allowlist (no `Edit` for checkers, no `Agent` for anyone). `next` prints
  `agent:` beside `model:`; the orchestrator passes both on dispatch.
- **Role prompt**: the engine's own dispatch text for a role,
  `scripts/roles/<role>.md` — one per `ROLES` entry (`proposer`, `critic`,
  `worker`, `unit-critic`, `verifier`), at most 20 lines, no heading,
  naming its role's invariant strings verbatim. `next` prints
  `prompt: <path>` (and `also_prompt:` for the Verify beside `check`)
  before any `overlay:`/`also_overlay:` line; `scripts/run-change roles
  prompt --store <slug> --role <role>` prints it, then — when the store
  has one — a blank line and the overlay, engine prompt always first.
- **Anchor**: one of six fixed phrases; a role prompt repeats each anchor
  assigned to its role exactly twice — once on its first line, once on its
  last — and carries no other (assignment: `specs/role-prompts`,
  `tests/run.sh`): `seam`, `fresh read`,
  `generator/checker split`, `smallest tier that can be wrong safely`,
  `turns, not tokens`, `the engine records, the worker never asserts`.
  Inside a role prompt the repetition is not deduplicated; human-facing
  prose keeps the usual terseness rule (**Hard rule: written for agents**
  in AUTONOMOUS-ORCHESTRATION.md).
- **Role overlay**: `<store>/openspec/roles/<role>.md` for one of
  `proposer`, `critic`, `worker`, `unit-critic`, `verifier` — project
  notes appended verbatim to that role's dispatch after the engine's own
  instructions. `next` prints `overlay: <path>` (and `also_overlay:` for
  the Verify beside `check`) immediately after the role's `prompt:` (and
  `also_prompt:`) line — see **Role prompt**; `roles get` prints the
  overlay text alone. Adds knowledge, never changes a contract: the
  engine's text wins on conflict.
- **Gate tree**: the `gate_tree` state field — the git tree id the last
  *passing* full gate ran on, written by `gate run --mode full` itself.
  The merge lane compares it to the tree after merging trunk in and skips
  the gate rerun when they are equal: same tree, same deterministic
  result. Any change to the tree (trunk moved, Archive commit in local
  mode) forces the rerun.
- **Merge lane**: the serialized merge-trunk-then-full-gate step behind
  `<store>/.orchestration/merge.lock`. Merges `origin/<trunk>` if that ref
  exists, else the local trunk — local-only projects are supported; a
  project with neither `origin/HEAD` nor a local `main`/`master` is
  refused with a clear error.
- **Initiative**: complex work decomposed into dependency-ordered changes.
  Its record, `<store>/.orchestration/initiatives/<name>.yaml` (`title`,
  `request`, `children` in merge order, `critique_rounds`,
  `last_critique_result`, `merged` as a `child=sha` map), is written only
  via `scripts/run-change initiative init|get|set|merged` and uses
  the state module's YAML dialect, but lives outside `state/` so `status`
  never lists it as a change.

The engine's own gate is `tests/run.sh` — black-box through the
`scripts/run-change` CLI, both seams substituted (temp registry, temp
project repo).
