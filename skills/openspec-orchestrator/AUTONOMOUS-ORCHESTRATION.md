# Autonomous change orchestration

Rule document for running OpenSpec changes. It is the **only** execution
mode of the `openspec-orchestrator` skill: whenever the skill is invoked on
a change, read this doc and run the three phases in [SKILL.md](SKILL.md) end
to end, asking the human only if something is wrong — plus exactly one
mandatory checkpoint that always fires regardless of whether anything is
wrong: **Gate 0**, after a clean critique and before any code is written
(Phases, step 3). The human never has to say "run autonomously" — that is
always assumed, and there is no step-by-step alternative to fall back to.
Stopping between phases to wait for approval is a bug everywhere except
Gate 0. Gate 0 is not optional and not a mode of its own — it is a
required step of every change, it repeats on every revision round, and it
has no cap: the flow cannot reach Apply without an explicit human accept.

The reader of this doc, the state files, and the scripts it drives is
another agent in a later session, not a human. Comments and state exist to
let that agent act correctly, not to narrate — see §8.

## Repo boundary (read this first)

This repo is the shared *engine*: this doc, `scripts/`, and the phase
definitions in [SKILL.md](SKILL.md). It ships once and applies to every
target project the `openspec-orchestrator` skill routes to.

A "change" always has two locations, never one:

- **Code and git history** live in the **target project's own repo** — the
  branch `change/<name>` and every commit on it belong to that repo. Its
  worktree is *checked out* under the store
  (`<store>/.orchestration/workspaces/<name>`, ignored by the store's git)
  so the project's main checkout never shows orchestration files; git
  still records the worktree in the project's `.git/worktrees`.
- **Spec artifacts and orchestration state** live in that project's
  **store** — the directory the `openspec-orchestrator` skill resolved via
  `--store <slug>` (slug recomputed from `git remote get-url origin`, kebab-
  cased; see that skill for the exact algorithm — there is no persisted
  mapping file, so always recompute, never cache a slug across sessions).
  That directory is usually a separate external root
  (`~/.local/share/openspec/stores/<slug>`), but when the project already has its own
  `openspec/` folder, the skill's Step 1 registers the project **as** the
  store (same slug, `local_path` pointing at the project itself) — see
  SKILL.md's local-mode routing. The two locations above then collapse into
  one directory, but the CLI-level split (`--store <slug>` for artifacts,
  plain project paths for code) is unchanged.

Orchestration config (`orchestration.concurrency`, `gate_quick`,
`gate_ui`, `gate_full`) lives ONLY in the resolved store's `openspec/config.yaml`.
`scripts/run-change` refuses a project that has its own `openspec/` folder
**only when** the store it's being pointed at is a genuinely different
external root — that combination means the wrong store was resolved for a
project that should be running in local mode instead (`guard_project_openspec`
in `scripts/lib.sh`). A project running in local mode (store `local_path` ==
the project) is never refused.

Runtime state (slots, merge lock, phase files, initiatives) lives under
`<store>/.orchestration/`, scoped to that one store/project. The concurrency
cap and merge lane in this doc are **per target project**, not global — two
changes against two different projects never contend for the same slot or
lock.

The `openspec` CLI has no built-in locking, concurrency, or phase-state
tracking (confirmed against v1.13.1 — `store setup` just creates a plain
git-backed folder). Everything below is userland, built from plain files.

## Phases

```
proposed → awaiting-acceptance → applying → checking → verified → archived → ready-to-merge → merged
```

plus `blocked` (see bug triage below). A `revise` answer at
`awaiting-acceptance` sends `phase` back to `proposed` (see Gate 0 below) —
the only backward edge in the diagram. State lives in
`<store>/.orchestration/state/<change>.yaml`:
`phase`, `propose_rounds`, `last_critique_result`, `prev_critique_result`,
`acceptance`, `fix_attempts`, `last_gate_result`, `gate_tree`,
`last_verify_result`, `prev_verify_result`, `initiative`, `depends_on`,
`seams`, `follows`, `supersedes`, `blocked_on`, `lifecycle`,
`manual_tasks_open`, `manual_accept`, `units`, `unit_deps`, `unit_tasks`,
`ui_units`, `parallel`. The last five drive the units loop (step 4 below):
`units` and `unit_deps` share the `seams` dialect (`<u>=<file>,<file>;...`
/ `<u>=<dep>,<dep>;...`); `unit_tasks` maps each unit to its tasks.md ids
the same way; `ui_units` is a bare `<u>,<u>` list; `parallel` is `""`,
`true`, or `false` (empty reads the store's `orchestration.parallel`, else
`true`). A per-unit file holds what the change file cannot (concurrent
unit workers would race a shared field): `<store>/.orchestration/state/
<name>.units/<unit>.yaml` — `status`, `iterations`, `base`,
`checks_commit`, `screenshot`, `critique`, `merge_attempts`. `acceptance` holds Gate 0's
pending human answer — `""` (waiting), `accepted`, or `revise` — and is
cleared back to `""` every time it is acted on, by whichever step consumes
it. `gate_tree` is written by `gate run --mode full`
itself, only when the gate passes: the git tree id it ran on. The `prev_*`
fields are written by `state set`
itself whenever a real `last_*_result` is overwritten — by a new result or
by the `""` written before a recheck; overwriting an empty value shifts
nothing — so the orchestrator never sets them. `lifecycle` is `full` or
`light` (empty reads as `full`); `manual_tasks_open` is the count `tasks
open` last recorded (`""` means never counted, a literal `0` means none
open); `manual_accept` holds `accepted:<requirement>[;<requirement>...]`
once the human accepts unverified requirements at the manual-task gate —
see **Lifecycle** and **Manual tasks** in CONTEXT.md.
Session history is a separate append-only log, one line per
orchestrator/worker run against this change, at
`<store>/.orchestration/state/<change>.sessions.log` (see **Session log**
in CONTEXT.md) — `role: orchestrator|worker|advisor|resume`, `phase`, `gates_hit`,
`transcript_id`, `model`, `tier`, written via `scripts/run-change session
append`, never edited after the fact.

1. **Slot** — before anything else, run the trunk preflight: `scripts/run-change
   gate run --store <slug> --project <path> --mode full --trunk` (SKILL.md Step 0
   check 4). It runs `gate_full` against the trunk ref in a temporary detached
   worktree, writes no state, and is removed whether it passes or fails. Red, or
   `gate_full` unconfigured, stops here — show the output, tell the human trunk is
   already red, open no change; the slot below is never acquired. Only then
   `scripts/run-change slot acquire --store <slug> --project
   <path>` before
   starting; blocks/queues if the project's concurrency cap (N, from the
   store's `openspec/config.yaml` `orchestration.concurrency`, default 2 —
   the disjoint-files check, not this cap, is what keeps concurrent
   changes apart) is full. A change `blocked` on a dependency releases its slot while
   waiting — a dependency can never deadlock the cap.
2. **Workspace** — `scripts/run-change workspace create --store <slug>
   --project <path> --name <name>`: branch `change/<name>` off the project's trunk,
   worktree checked out under the store's `.orchestration/workspaces/`,
   dependencies synced. A project with no repo or no commit yet (an empty
   folder the first idea landed in) is initialized first — `git init -b
   main` and an initial commit of whatever is there — by the same command
   (`ensure_project_git`), mirroring Step 0 check 3 of SKILL.md; nothing
   downstream ever sees a project without a trunk. Never dispatch work against the project's main
   checkout — and every gate (`gate run ... --name <name>`) runs in the
   worktree, never in the main checkout, which is trunk and says nothing
   about the branch.
3. **Propose** — runs at the `deep` tier (see Model/effort routing
   below), regardless of how small the change looks: a mistake here is the
   most expensive one, because every later phase inherits it — unless the
   project mapped its own skill to `plan` (**Project-skill stage mapping**
   under Model/effort routing), in which case that skill drafts instead.
   Under `lifecycle: light` (see below), Propose and any `revise` round run
   at `standard` instead — the critic still resolves one tier above, to
   `deep`, via the generator/checker split.
   Propose is three `next` steps, not one: `classify`, then `grill`
   unless the change is trivial, then `propose`.

   **Classify** (`standard`): read the request and the code, then record
   the four pillar readings in state — `state set ... pillars
   "scope=<file|seam|seams>;blast=<none|project|public>;novelty=<known|new>;deps=<none|dev|runtime>"`.
   **Scope**: one file, one seam, or several seams. **Blast radius**: what
   else breaks if this is wrong — nothing outside the seam, callers inside
   the project, or a public API, schema, or contract another caller relies
   on. **Novelty**: a known pattern in this codebase, or new logic.
   **Dependency impact**: no new dependency, a dev-only one, or a runtime
   one, external service, or shared state. Values outside those lists are
   refused by `next`. Read them for the code as it is, not for the request's
   tone: the critic grades the readings later and a pillar read low to
   earn the fast path is `blocking`.

   **Grill** (tier `none`, the orchestrator itself): `next` returns it when
   any pillar reads above `scope=seam`, `blast=none`, `novelty=known`,
   `deps=none` and `grill` is not yet `done`. Run grill mode's in-change
   entry (SKILL.md **Grill mode**): the analysis round, then `grilling`
   and `domain-modeling` writing the Project glossary and ADRs under the
   root's `openspec/`, then `state set ... grill done`. This is the one
   interview inside a change, and it is where the human settles *what*
   and *how*; "make every decision yourself" governs everything after it,
   never instead of it. A greenfield folder with new logic or a public
   contract is the case this exists for: expectations get set before a
   proposer invents them. The human may decline the interview with
   `state set ... grill skipped:human`, which `next` treats as done; the
   engine never skips it on its own for a non-trivial change.

   **Propose** (`deep`): draft. The classification decides the shape, and
   nothing else does: trivial on every pillar is a **fast-path fix** —
   grill skipped, the extended exploration otherwise done here skipped,
   the smallest delta spec that captures it, and Gate 0 offers `light`;
   blast radius or dependency impact beyond the project, or parts that
   would merge independently, is an **initiative** (**Initiatives**
   below), not a change; everything else is an ordinary `full` change.
   The proposal repeats the four readings, one line each, and cites the
   glossary terms and ADRs grill wrote. Reclassify — update `pillars` and
   say so in the proposal — if the code turns out to read higher on any
   pillar than classify did; a reclassification out of trivial sends the
   change back through `grill`. The proposer states the classification; it
   is the critic, below, who accepts or rejects it — a proposer never
   lowers its own scrutiny. The proposal also carries a
   **Guardrails** line: what this change must not introduce (a new
   dependency, a new abstraction, a changed public signature, a widened
   seam), named concretely, so the critic and Verify have a negative to
   grade against and not only requirements to tick. Before drafting prose, sketch the
   **seams** the change touches:
   existing seams preferred over new ones, fewest possible (one is ideal),
   each seam named with the files/modules behind it. Write this seam list
   to the change's state (`scripts/run-change state set ... seams
   "<seam>=<file>,<file>;<seam>=<file>"` — see **Seam list** in
   CONTEXT.md), not just narrated in the delta spec prose — it is the input
   units are cut along in step 4 and what the disjoint-files
   check reads, not a separate exercise redone at Apply time. Log the
   session entry with `phase proposed` before the critique below runs.

   **Critique** — nothing downstream can catch a wrong spec, because Apply
   builds to it and Verify grades against it. So before the spec is
   committed, a critic with a fresh context and a model one tier above the
   proposer's (`scripts/run-change model critic --store <slug> --name
   <name>`; see the generator/checker split under Model/effort routing)
   reads its fixed **input contract** — the originating request, the draft
   delta spec, the seam list, the store's Project glossary
   (`openspec/CONTEXT.md`) and ADRs (`openspec/adr/`) when present, and the
   prior critique report on round 2+ — never the proposer's transcript, and
   never told to go explore the codebase at large; it may read other files
   only to confirm a seam is real or a dependency claim true. `model critic`
   prints this contract as `input:` lines after the bare model id — include
   them verbatim in the dispatch. When present, a proposal contradicting an
   ADR is `blocking` unless it names the ADR it supersedes; a non-canonical
   term is a `warning`. It judges the draft on five standards. If the project mapped one or more skills to
   `critic` (**Project-skill stage mapping**), each of them is dispatched
   **concurrently** with this checker, reads the same inputs, and reports
   alongside it — not instead of it; the step waits for all of them and
   merges the reports.
   - **Fidelity**: every part of the request is covered, nothing beyond it
     is added.
   - **Seams are real**: each named file exists, is where that behavior
     actually lives, and the list is complete — a missing file here breaks
     the disjoint-files check silently.
   - **Testable**: each requirement has a scenario a Verify checker could
     grade the code against without guessing. The same standard applies to
     the proposed implementation *approach*, not only requirement text: an
     approach the critic cannot see how to verify, or sees a concrete way
     for it to fail, is `blocking` — never advisory — and when the critic
     can name a fix, that fix is the finding's remedy.
   - **Right size**: smallest change that satisfies the request; the four
     pillar readings are honest for the code as it is (a pillar read low
     to earn the fast path is `blocking`), the resulting shape — fast-path,
     `full`, or initiative (see below) — follows from them, the change is
     not padded, and the Guardrails line names real risks for this seam
     rather than generic ones. Verify later grades the diff against that
     line as it does against every requirement.
   - **Written for agents**: the hard rule at the end of this doc.

   The critic writes a **critique report** to
   `<store>/.orchestration/state/<name>.critique.md` (overwritten each
   round) and sets `last_critique_result` per the **Checker loops** rules
   below — severity, pass line, convergence, and budget are defined once
   there:
   - `clean` or `warnings:<m>` — pass. Warnings are fixed in place at the
     mechanical tier, no re-critique. Commit the spec and seam list on the
     branch, then set `phase: awaiting-acceptance` and go to **Gate 0**
     below — Apply never starts on a draft the human hasn't accepted.
   - `blocking:<n>` — the proposer (same `deep` tier) revises only what the
     findings name, logs another `proposed` entry, and the critic reruns
     with the prior report. `propose_rounds` counts these, cap 2. Out of
     rounds or not converging → **Gate 1** with the latest report and
     draft: the request is cheaper to clarify now than to build wrong.
   - `request` — the originating request is itself contradictory or too
     ambiguous to draft against. → **Gate 1** immediately.

   `blocking` and `request` reach a human through Gate 1 only when the
   critic itself could not get the draft clean. Gate 0 below is the
   opposite case — a draft the critic passed — and it still always asks:
   passing the critic is not the same as the human wanting this built. The
   same critique, same standards where they apply, runs on every other
   deep-tier artifact — see **Critique beyond the spec** below.

   **Gate 0 — proposal acceptance.** `phase: awaiting-acceptance`, driven
   by the `acceptance` field (`""` pending, `accepted`, `revise`), no round
   cap. While `acceptance` is empty, `next` returns `action: gate0`:
   nothing downstream is dispatched, and repeating `next` with no state
   change is expected here — the missing input is a human answer, not a
   computation. On this action:
   1. Draft a **short resume** — a few sentences, not the delta spec —
      of what is about to be implemented, and show it to the human, with
      the proposal's four pillar readings and its Guardrails line as
      written (the human is choosing `light` or `full` on exactly that
      classification, and the critic has already checked it).
   2. In the same turn, offer to show the full proposal
      (`openspec show <name> --store <slug>`) and ask whether to accept or
      request changes. Showing the full proposal is not itself an answer —
      still get an accept-or-revise after it. For a proposal Propose
      classified as a fast-path fix, the choice gains a third option,
      **"Accept — light lifecycle."** State what it changes: drafting and
      `revise` rounds run at `standard` (the critic still resolves one tier
      above, to `deep`); Apply continues the proposer's worker where the
      host can resume an agent, else dispatches a fresh `standard` worker;
      a green gate with `warnings:<m>` skips the sweep round. For a change
      already drafted at `deep` and critiqued at `max` before this Gate 0,
      only that last part — the sweep skip — is still ahead of it. State
      what it never skips: Gate 0 itself, the full gate (incl. the
      dead-code pass), Verify, the manual-task block, Gate 2. Ask
      accept-or-revise (or accept/light/revise) as a
      structured choice (e.g. buttons) when the host interface offers one,
      not only as free text — this changes presentation only, never the
      valid answers.
   3. Record the answer:
      - **Accept** — `scripts/run-change state set --store <slug> --name
        <name> acceptance accepted`. `next` then returns `apply` with
        `set_phase: applying` and clears `acceptance` back to `""`, so a
        later revision of this same change starts Gate 0 clean.
        `lifecycle` stays `full`.
      - **Accept — light lifecycle** (offered only for a fast-path
        proposal) — `scripts/run-change state set --store <slug> --name
        <name> lifecycle light acceptance accepted` (auto-inits
        `lifecycle` if unset). `next` then returns `apply` the same as
        plain Accept. Besides triage opening a bugfix change (**Bugs found
        mid-run**, below), this is the only way `lifecycle` becomes
        `light` — the orchestrator never picks it on the human's behalf
        for any other change.
      - **Request changes** — write what the human wants changed to
        `<store>/.orchestration/state/<name>.feedback.md` (overwritten
        each round, same convention as the critique/verify reports), then
        `state set ... acceptance revise`. `next` returns `propose` at the
        `deep` tier with `set_phase: proposed`. Before dispatching it,
        clear `last_critique_result`, `prev_critique_result`,
        `propose_rounds`, and `acceptance` back to `""` — this is a full
        restart of step 3 above, not a patch: the proposer drafts again
        from the original request *and* the feedback file, the critic
        reruns against the new draft, and a clean result lands back at
        `awaiting-acceptance` with a new short resume. Gate 0 is not a
        one-time checkpoint — it fires again on every round, with no cap,
        until the human accepts.

   Gate 0 never runs the fixer, the fix-round budget, or the convergence
   test under **Checker loops** — those exist for a checker finding, and a
   request for changes here is a human choosing a different draft, not a
   defect report. It never skips, either: a change that already cleared
   Gate 0 once and comes back for a `revise` round goes through it again,
   in full, on the new draft.
4. **Apply** — `apply` itself is bookkeeping, tier `none`: commit whatever
   `git status --porcelain` shows in the change worktree (proposal
   artifacts in local mode; a pre-1.4.0 change resumed straight into
   `applying` may also hold uncommitted wave edits from before units
   existed), record `phase: applying`, and call `next` again — no worker
   is dispatched on this step. Implementation runs in **units**: each
   independent slice of the Propose step's seam list gets its own
   worktree, branch, and Agent, reviewed and merged on its own before
   Check/Verify ever run.

   **Split.** With `units` empty, `next` returns `split` — tier `deep`
   under `lifecycle: full` with parallel mode on (the generator): it reads
   the seam list and tasks.md and writes four state fields, `units`
   (`<u>=<file>,<file>;...`, the seam dialect), `unit_deps`
   (`<u>=<dep>,<dep>;...`), `unit_tasks` (`<u>=<task-id>,...;...`), and
   `ui_units` (`<u>,<u>`), then runs `units check` (state-only: acyclic
   deps, every dep a known unit, every file in some `seams` group, two
   units with overlapping files ordered by a dep path, every task id in at
   most one unit — the CLI also prints `unassigned: <id>` for a tasks.md
   id in no unit, not an error). Under `lifecycle: light` or `parallel:
   false` (**Single-worker baseline** below), `split` instead runs `units
   single [--ui]` at tier `none`: one unit `all` holding every seam file
   and every task id. A change too small to have named more than one seam
   still goes through `split` and gets one unit. Prefer a **flat** split:
   one scaffold or contracts unit that everything depends on, then leaves
   that depend only on it. A chain (A → B → C → D) serialises the wave,
   and each link's defects cost every unit after it a rerun; a dependency
   edge is for a real compile-time or test-time need, not for "it feels
   earlier".

   **Spawn.** The scheduler, `units next`, lists ready units (no dep
   outstanding, in `units` field order) up to the free capacity
   (`orchestration.unit_concurrency`, default 3 — a unit `running`,
   `reviewing`, `conflict`, or `resolving` holds a slot). `next` returns `unit-spawn` naming the ready units; the
   orchestrator runs `unit create --unit <u>` for each (branches
   `change/<name>.<u>` off the tip of `change/<name>` into
   `<ws>/<name>.<u>`, refusing an unknown unit, a dep not yet `merged`, or
   a dirty change worktree) and dispatches one Agent per unit into that
   worktree at the tier `unit_tiers` names for it — `deep` for a
   **foundation unit** (two or more units depend on it directly: it
   serialises the wave, and a defect in it costs every dependent a rerun),
   `standard` for a leaf or a link with a single dependent; `unit create`
   records that tier on the unit's state file — see
   **Unit workers** below for the dispatch contract and the check-first
   loop it runs (`unit iterate`, capped at 5).
   Units with no dependency between them run concurrently, each in its own
   worktree and branch, so none of the Isolation or disjoint-files
   reasoning about a shared worktree applies to them; a dependent's
   worktree is only created after its dep has merged onto `change/<name>`,
   so it starts from the dep's own code.

   **Pass without a critic.** Under `lifecycle: light` only: a unit that
   is not in `ui_units`, is a `standard` leaf, went `green` on iteration 1,
   and has no critique yet gets `unit-pass` (tier `none`) instead of a
   critic: `unit pass --unit <u>` re-checks every one of those conditions
   itself, sets `status reviewed` with `critique: skipped`, and logs `role
   orchestrator phase unit unit <u> event critique-skipped reason
   light-leaf-green-first-iteration`. Measured: unit critics over such
   leaves found nothing, at the top tier's price; Verify still reads the
   whole merged diff, so the unit is reviewed once rather than twice. A
   second iteration, a screenshot, a foundation tier, or a `full`
   lifecycle each keep the critic.

   **Critique.** Once a unit goes `green`, `next` returns `unit-critique`
   (checker one tier above *that unit's worker*: `deep` over a `standard`
   leaf, `max` over a `deep` foundation unit — `model critic --unit <u>`;
   green units at different tiers are dispatched in separate calls) over
   `units ready-for-review`: the critic reads the unit's diff from its `base`, the
   checks diff to its `checks_commit`, and every recorded screenshot, and
   its report must quote the unit's recorded screenshot path verbatim for
   a UI unit. Clean or warnings → `status: reviewed`. Blocking, within the
   cap → `unit-revise` (same worker, same cap); out of cap → `gate1`. On
   `unit-revise` the orchestrator sets `unit set --unit <u> status running
   critique ""` before resuming or re-dispatching the worker — otherwise the
   unit stays `reviewing` with a blocking critique and a repeated `next`
   dispatches the same worker again, and once the revised worker's `unit
   iterate` goes green the unit is left with a stale blocking critique
   instead of being picked up by `unit-critique`.

   **Merge.** A unit `reviewed` with every dep `merged` yields `unit-merge`
   (tier `none`, in `units merge-order`): rebase the unit branch onto
   `change/<name>`, fast-forward the change branch, tick the unit's task
   ids in tasks.md, remove the unit worktree and branch. A rebase conflict
   → `merge-conflict` (`standard`, confined to the conflicting files, one
   attempt) then `unit merge` again; a second conflict, or a `resolving`
   unit whose rebase never finished, → `failed` → `gate1`. This merging
   happens inside the units loop itself, not in step 8's merge lane — a
   dependent cannot start until its dep's code is actually on
   `change/<name>`.

   Once every unit is `merged`, `next` returns `units-merged` with
   `set_phase: checking`, and step 5 below runs the existing full gate and
   Verify on the change branch, unchanged — the units loop only replaces
   how the code gets onto that branch, not what checks it afterward.

   Under `lifecycle: light`, `split` still runs `units single` and the
   loop above runs for that one unit `all`; its worker is the proposer's
   own session resumed where the host can resume an agent, else a fresh
   `standard` worker — `next`'s output is identical either way. Any test
   fixture that takes seconds to build — a compiled binary, a bundled app,
   a container image — is built once per test run into a shared fixture (a
   `before`/global/session hook, not a per-test or per-file one); Verify
   reports a per-test or per-file rebuild as a warning.
5. **Check** — run the project's *full* gate
   (`orchestration.gate_full`, parallelized if the project's test runner
   supports it) **and dispatch Verify (step 6) at the same time**: both
   only read the tree the orchestrator just committed, so neither waits
   for the other (`next` returns `check` with `also: verify` and the
   checker's `also_model`). Record both results as they land. The pass
   line is unchanged — green *and* clean — so this costs at most one
   partly wasted checker call on a red gate and saves a full checker
   latency on every change. The full gate must include the project's
   **dead-code pass** — `knip` for JS/TS, `vulture` for Python, the ecosystem's
   equivalent otherwise — reporting unused files, unused exports and
   unused dependencies as one red result. Agents leave abandoned work
   behind: an approach tried and replaced, a dependency pulled in for an
   idea then dropped, a helper refactored past. None of it fails a test,
   so a passing suite cannot see it, and Verify reads the diff against
   the proposal, not the whole graph. Only a graph tool in the gate does.
   Its red is a normal fix round, triaged to `mechanical`: delete what it
   names.
   - Red: a **fix round** (see below). If Verify has already reported, the
     fixer gets the gate failure *and* the verify report and fixes both in
     that one round; a verify result of `spec` gates immediately instead,
     and the convergence test on the verify count applies as under green.
     Out of rounds → **Gate 1**: ask the human with the failure.
   - Green: act on the Verify result below; if it is not in yet, wait for it.
6. **Verify** — dispatched together with step 5. A checker with a fresh
   context and a model one tier above
   whichever one last wrote code for the change (`scripts/run-change model
   verify --store <slug> --name <name>` — see the generator/checker split
   under Model/effort routing) reads its fixed **input contract** — the
   proposal, the seam list, the branch diff, and the prior verify report on
   round 2+ — never the implementer's transcript, and never told to go
   explore the codebase at large; it may read other files only to confirm
   a seam is real or a dependency claim true. `model verify` prints this
   contract as `input:` lines after the bare model id — include them
   verbatim in the dispatch. It judges whether the code satisfies the
   proposal, including its Guardrails line — a diff that introduces what
   that line forbids is `blocking` like any unmet requirement; a
   requirement left as a manual task when a programmatic proxy
   exists is reported as a `spec` finding, not left unverified silently.
   It also reads the store's `openspec/config.yaml`: a diff that adds or
   renames an `orchestration.*` key, adds a role overlay, or changes a
   convention the `context:` block states, without updating that file, is
   one `warning` finding — the mechanical sweep then edits the config, the
   same as any other warning. Architecture lands in the living spec at
   Archive by itself; conventions only stay current if someone asks.
   If the project mapped one or more skills to
   `test` (**Project-skill stage mapping**), each of them is dispatched
   **concurrently** with this checker, reads the proposal and diff, and
   reports alongside it — not instead of it; the step waits for all of
   them and merges the reports. It writes a **verify report** to
   `<store>/.orchestration/state/<name>.verify.md`, overwritten each
   round, and sets `last_verify_result` per the **Checker loops** rules
   below. Every finding names the proposal requirement, the `file:line`,
   what is wrong, what would satisfy it, and a severity; no finding without
   all five.
   - `clean`, or `warnings:<m>` under `lifecycle: light` — pass, and the
     sweep below is skipped. Continue to the manual-task check in Archive
     (step 7).
   - `warnings:<m>` under `lifecycle: full` — pass. Warnings
     (human-narrative comments, oversized artifacts, the hard rule at the
     end of this doc) get one mechanical-tier sweep and a quick gate, no
     re-verify, not a round. Then continue to the manual-task check in
     Archive (step 7).
   - `blocking:<n>` — the code falls short of a proposal requirement. The
     report is the input to a **fix round** (below): set `phase: checking`,
     fix, rerun step 5, then re-run Verify. Out of rounds or not converging
     → **Gate 1** with the latest report.
   - `spec` — the proposal itself is wrong, ambiguous, or silent on what the
     code does (including a requirement left manual when a programmatic
     proxy exists), so no code change can close the finding. → **Gate 1**
     immediately: the human owns the spec in autonomous mode, and a fix
     round that edits the proposal would be the code grading itself. When
     the human approves the amendment, record `state set ... spec_amend
     accepted`; `next` then returns a `fix` at `deep` whatever the round
     number — rewriting the delta spec and its checks is design work, and
     a `standard` fixer here has needed a second round to get the checks
     right. The fixer clears `spec_amend` with the two result fields.
7. **Archive** — runs only from phase `verified`, and getting to `verified`
   is itself gated on the change's own tasks.md, not just the gate and
   Verify results above. The action that gets there — `tasks-open`, with
   `set_phase: verified` — runs `scripts/run-change tasks open --store
   <slug> --name <name>`: it prints the change's unchecked `- [ ]` task
   lines and records their count in `manual_tasks_open` (a literal `0`
   when none are open). At `verified`, `next` checks that count before
   ever returning `archive`:
   - `manual_tasks_open` empty — never counted (a fresh or pre-1.3.0 state
     file, or `verified` recorded by hand) — returns `tasks-open` again,
     with no `set_phase`; count first.
   - `manual_tasks_open` greater than 0 and `manual_accept` empty — returns
     `gate2-manual`: show the human the open task list alongside the
     verify report, so they can judge each one without waiting for Gate
     2's material. They resolve it by ticking off each task they confirm
     done (the orchestrator edits `- [ ]` → `- [x]` in tasks.md, then reruns
     `tasks open`) or by recording `scripts/run-change state set --store
     <slug> --name <name> manual_accept accepted:<requirement>[;<requirement>...]`
     naming the unverified requirements — `accepted:` with nothing after
     the colon is refused. "Worth trying yourself after merge" is never
     offered as an answer here.
   - `manual_tasks_open: 0`, or `manual_accept` set — returns `archive`.
     Only here does `next` allow `--yes` on `openspec archive`: the CLI
     (1.13.1) refuses to prompt-skip on a non-TTY over unchecked tasks, and
     also whenever a delta spec updates even with every task checked, so
     `--yes` is required for any normal change — the recorded count or
     `manual_accept` is the guard, never the flag by itself. Archive then
     finalizes artifacts (`openspec-orchestrator` archive phase) and
     commits on the branch.
8. **Merge lane** — `scripts/run-change merge-lane run --store <slug>
   --project <path> --name <name>`: acquire the project's single
   merge lock, merge current trunk into the branch (`origin/<trunk>` when
   the project has a remote, the local trunk when it has none; trunk is
   `origin/HEAD`, else local `main`, else `master`), then rerun the full
   gate — **unless the merged tree is identical to the one the last
   passing full gate ran on** (`gate_tree` in the state file, recorded by
   `gate run --mode full` itself), in which case the rerun is skipped and
   the command says so: same tree, same deterministic result. Trunk having
   moved, or an Archive commit that touched the worktree (local mode),
   changes the tree and forces the rerun. Red → a fix round (same
   budget). Green or skipped → **Gate 2**: ask the human with a summary
   (diffstat, gate log, verify report, and — when `manual_accept` is set —
   the accepted-unverified requirements it names; and — under
   `lifecycle: light` — the unswept Verify warnings, since light skips the
   mechanical sweep that would otherwise have cleared them).
9. **Merged** — on approval, squash-merge into trunk (one commit, with the
   trailers below), remove the workspace, release the slot. If the change
   belongs to an initiative, record the commit on it first:
   `scripts/run-change initiative merged --store <slug> --name
   <initiative> --child <name> --commit <sha>` — the initiative record
   outlives the child's state file.

Everything between gates is autonomous. Commits on `change/<name>` never
ask. Squash-merge produces one commit per change on the project's trunk.

## Unit workers

A unit worker's dispatch carries the proposal and delta spec, its unit's
task ids and their tasks.md text, its file list, its worktree path, the
engine path, the commands below, the engine's worker prompt
(`scripts/roles/worker.md`, surfaced by `next` as `prompt:`), and the
store's `worker` overlay when `next` printed one (**Role overlays**) —
never another unit's transcript.

- **Checks first.** Step 1, before any implementation: write executable
  checks — unit tests in the project's own runner for each requirement the
  unit's tasks implement, and for a unit in `ui_units`, a Playwright
  script. Commit them, then `unit checks-done --unit <u>`, which records
  the unit branch HEAD as `checks_commit` and refuses while HEAD still
  equals `base` (nothing committed yet). `unit iterate` refuses until
  `checks_commit` is set. The checks must be part of what `gate_quick`
  runs — or `gate_ui` for a UI unit's Playwright script — so the critic's
  `git diff base..checks_commit` is read against the same thing the loop
  below actually checks.
- **UI layout invariants.** A Playwright script for a UI unit launches the
  page at 1280×800 and writes a full-page screenshot to `$UNIT_SCREENSHOT`
  only when `$UNIT_NAME` equals the unit that owns that test (both
  exported by `unit iterate`) — a non-owning unit's UI test still runs and
  asserts, it just writes no file, so the recorded PNG is always the
  iterating unit's own view. It asserts: the board/canvas element's
  bounding box lies inside the viewport; the page has no horizontal
  overflow; every SVG shape has a computed `fill` or `stroke` other than
  `none`/transparent; every cell of a DOM-grid board has a non-transparent
  computed background; plus one assertion per requirement the unit
  implements. `playwright` is the one dependency a worker may add — a
  target-project devDependency, only when the unit is in `ui_units` and
  the project lacks it, listed in that unit's files (so `units check`
  orders every other unit touching `package.json`/the lockfile after it)
  and visible in the Gate 2 diffstat. The browser binary itself is a
  machine-level cache download outside the project, done once before a run
  with the human's approval. The engine never depends on Playwright.
- **The loop.** Implement, then `unit iterate --unit <u>` — the engine, not
  the worker, runs `gate_quick` in the unit worktree with
  `UNIT_SCREENSHOT`/`UNIT_NAME` exported, then — for a unit in `ui_units`
  only — `orchestration.gate_ui` (the Playwright run) in the same shell,
  and derives green/red from the combined exit code (green for a UI unit
  also requires the PNG to exist). `gate_quick` stays under ~30 s: type
  check, unit tests, nothing that launches a browser; a Playwright run in
  `gate_quick` is paid by every non-UI unit on every iteration (measured:
  28 s × 17 iterations on one change). Put it in `gate_ui`; a store with
  no `gate_ui` runs `gate_quick` alone for UI units as before. Fix on
  red, iterate again; at most 5 iterations (`UNIT_ITER_CAP`) — a 6th call
  is refused and the unit is marked `failed`. The worker never asserts its
  own result; the recorded `checks` value always comes from a command the
  engine ran.
- **Git.** A unit worker commits only on its own unit branch, only its
  unit's files (`git add -- <files>`, never `-A`), with trailers `Change:
  <name>` and `Unit: <u>`. It never pushes, rebases, merges, checks out,
  resets, or touches any other branch, and it never edits tasks.md —
  concurrent units would race it; `unit merge` ticks the unit's tasks once
  it lands on `change/<name>`.
- **Turns, not tokens, are the cost.** A worker's dispatch tells it to
  issue independent tool calls in one turn (several Reads, a Read plus
  the Bash check it does not depend on) rather than one per turn: on a
  100K+ context every round-trip pays full latency, and the measured
  workers averaged one tool per turn across 50–160 turns.
- **Session log shapes** (all `phase=unit`): spawn —
  `role worker phase unit unit <u> event spawn tier <t> model <m>
  transcript_id <id>` (orchestrator, at `unit-spawn` and `unit-revise`,
  `<t>` from `unit_tiers`); iterate — `role worker phase unit unit <u>
  event iterate iteration <n> checks <green|red> tier <t> model <m>`
  (written by `unit iterate` itself, `<t>` from the unit's state file); critique — `role critic phase unit unit <u> event critique
  iteration <n> tier <t> model <m> transcript_id <id>` (orchestrator, at
  `unit-critique`); conflict agent — `role worker phase unit unit <u>
  event merge-conflict tier standard model <m> transcript_id <id>`; merge
  — `role orchestrator phase unit unit <u> event merge result
  merged|conflict|failed` (written by `unit merge` on every rebase
  attempt; a refusal logs nothing); and once every unit lands, `role
  orchestrator phase unit event units-merged`. The orchestrator sets
  `status reviewing` before dispatching a unit critic, `status resolving`
  before dispatching the merge-conflict agent, and `status running
  critique ""` before resuming or re-dispatching the worker at
  `unit-revise`, so a repeated `next` never dispatches the same work
  twice.

## Isolation

Three layers keep concurrent agents from corrupting each other. They are
independent: each one holds even if the others are misconfigured.

- **Context.** Every worker — unit worker, fixer, critic, Verify, triage
  — runs in its own context window. It receives exactly what the
  orchestrator hands it (proposal, its seam's file list, its task, a
  report) plus what it reads from disk itself; never another worker's
  transcript, and never the orchestrator's. For the critic and Verify
  specifically, "what the orchestrator hands it" is the fixed **checker
  input contract** (Model/effort routing, below) — never "go explore the
  codebase"; anything beyond that contract is read only to confirm a seam
  is real or a dependency claim true. A wrong guess made in one
  window cannot spread to another except through a file, and every file
  that crosses between agents (spec, seam list, state, reports) is
  something the next reader can check against the code. This is the
  default when dispatching a subagent; the rule is to never defeat it by
  pasting one worker's output into another's prompt as fact.
- **Files.** Two writers may run at once only if the file lists behind
  their seams are disjoint — the check below. A worker writes only inside
  its own seam's list; a file it needs that isn't listed is a mid-run
  seam-list finding (below), not a silent edit. **A read-only worker is
  always collision-safe**: critic, Verify, triage, and any investigation
  never write, so they never need the check and may run beside any writer
  in any worktree. The one caveat is coherence, not collision — a checker
  reading a worktree while a writer is mid-edit sees a torn tree. So
  checkers start after the wave they judge has returned and been
  committed; they may overlap freely with writers in other worktrees.
- **Git.** Every change has its own worktree on its own branch (step 2), so
  changes never share an index or a working tree. Units carry this one
  level deeper: each unit also gets its own worktree and branch
  (`change/<name>.<u>`), so a unit worker is the only writer of its own
  index and HEAD, and committing there corrupts nothing else — this is the
  one exception to "workers never run any git command that writes." A unit
  worker commits its checks and each green iteration on its own branch only
  (`git add -- <files>`, never `-A`; trailers `Change:`/`Unit:`), and never
  pushes, rebases, merges, checks out, resets, or writes any other branch.
  The merge-conflict agent is the other exception: confined to the one
  unit worktree, it may run `git rebase change/<name>` and resolve only the
  files `unit merge` named. Every other worker — fixer, critic, Verify,
  triage, and a unit worker outside its own branch — never runs a git
  command that writes. The orchestrator is the only other committer: on
  `apply` (the change worktree), once per phase after that, and via `unit
  merge` (none tier) integrating a reviewed unit onto `change/<name>`. A
  worker that wants to "save its progress" returns instead.

## Disjoint-files check

The one rule that gates every concurrency decision in this doc, at either
granularity it applies to:

> Two units of work may run at the same time only if the file lists behind
> their seams don't overlap. If they overlap, run them in dependency/seam
> order instead — never concurrently, and never merge the lists to "make it
> fit."

Seam file lists come from the change's state, not the delta spec prose:
each change's `seams` field (written during Propose, step 3 — see
**Seam list** in CONTEXT.md), read via `scripts/run-change state get
--store <slug> --name <change>`. Nothing infers them after the fact, and
nothing parses the delta spec to reconstruct them. The check applies at
three granularities, same rule, same data source:

- **Within a change, across its units** (step 4): units are the
  intra-change concurrency unit. Each unit gets its own worktree and
  branch, so concurrent units never share a working tree or index — the
  check instead guards the split itself: `units_check` (state-only, run by `split` and by `next`)
  rejects two units whose file lists overlap unless they are ordered by a
  dep path. Overlap along a dep path is allowed, not disjoint, because a
  dependent's worktree is created only after its dep has merged onto
  `change/<name>`, so it starts from the dep's own code and the two units
  are never writing the same file at the same time even though their
  lists overlap on paper. Read-only workers are outside the check entirely
  (see **Isolation**).
- **Within a unit, at merge time**: `unit merge` independently refuses a
  unit branch whose diff touches a file outside that unit's own list —
  `units_check` catches a bad split before any worker starts, this catches
  a worker that drifted outside its list despite the split being sound.
- **Across a project**, among in-flight initiative children: compare the
  `seams` field of every child not yet merged before starting a new one
  concurrently, on top of (not instead of) the `depends_on` ordering.

A file list that turns out to be wrong once real implementation starts
(a shared barrel export, config, or type file no seam sketch named) is a
mid-run finding, not a silent merge: fall back to sequential for the
units/children involved and fix it with `state set ... seams "..."`, the
same command that wrote it.

## Driving the loop: `next` decides, the agent does

The lifecycle above is long. Do not hold it in your head and re-derive
the next step each turn; ask the engine:

```
scripts/run-change next --store <slug> --name <change>
```

prints one step — `action`, `tier`, resolved `model`, the `set_phase` to
record when the step completes, and the `reason` (which rule fired) — from
the change's state file and session log alone. On `check` it adds `also:
verify` and `also_model: <id>`: a second, read-only step to dispatch
concurrently with the first, never a replacement for it. On a role-bearing
action `next` also prints `prompt: <path>` right after `reason:` (and
`also_prompt: <path>` right after `also_model:` on `check`) — the engine
prompt for that role; see **Role overlays** above. Actions: `classify`,
`grill` (tier `none` — the orchestrator runs the interview itself),
`propose`, `critique`, `revise`, `gate0`, `apply` (tier `none` — bookkeeping only, no
worker dispatched), `split`, `unit-spawn`, `unit-critique`, `unit-revise`,
`unit-merge`, `merge-conflict`, `units-merged`, `check`, `fix`, `verify`,
`sweep`, `tasks-open`, `archive`, `merge-lane`, `gate1`, `gate2-manual`,
`gate2`, `wait`, `done`. The caps
(`FIX_CAP`, `PROPOSE_CAP`), the fix-round tier ladder, the pass line, and
the tier-above checker rule all live in `next_action`
(`scripts/lib.sh`), so the orchestration is deterministic code and the
agent's job is the step itself: dispatch the worker `next` names, then
record what happened (`state set ... last_gate_result green|red`,
`last_verify_result ...`, `fix_attempts`, `propose_rounds`, `phase`) and
ask `next` again. `last_gate_result` is `green` or `red`; nothing else.

`next` is read-only and never dispatches — the orchestrator still owns
gates and workers. What it removes is the decision. If the prose in this
document and `next_action` ever disagree, fix the prose: `next_action` is
what runs, and `tests/run.sh` walks a change through every branch of it.

## Resumability

`scripts/run-change status --store <slug>` discovers state from
`<store>/.orchestration/`, not chat memory, and `next` resumes any change
from its recorded fields. Commit on the branch after every
phase, so an interrupted run loses at most one phase. Re-running with no
arguments resumes each in-flight change from its recorded phase, checking
for uncommitted work first. A change resumed straight into `applying` from
before units existed may hold uncommitted wave edits from the old Apply;
before acting on `split` for it the orchestrator commits whatever `git
status --porcelain` shows in the change worktree, the same as `apply`
itself does on every change — `unit create` refuses a dirty change
worktree, so a missed commit here fails loudly instead of silently
dropping that work from every unit's `base`.

## Bugs found mid-run: ownership decides

Classify every red gate or verify finding by where the broken code lives —
this follows from file ownership, not judgement:

- **Inside the current change's scope**: fix in place, counts as a fix
  round. Never split out — a split change would depend on unmerged work.
- **Outside scope and blocking**: open a bugfix change autonomously, with
  `lifecycle: light` set on it (`scripts/run-change state set ... lifecycle
  light`, which auto-inits — skip full planning artifacts, proposal limited
  to symptom/cause/relations, plus a regression test), add a `depends_on`
  edge, set the current change to `blocked` with `blocked_on`, release its
  slot. The fix branches from trunk; once merged, the blocked change merges
  trunk in and resumes. Triage here and the human's "Accept — light
  lifecycle" at Gate 0 are the only two ways `lifecycle` becomes `light` —
  the orchestrator never picks it for any other change.
- **Outside scope and not blocking**: record a queued sibling with
  `follows: <current>`, no dependency edge; runs when a slot frees. Fixing
  it in place is scope creep.
- **In the change's own planning artifacts**: fix in place. In
  shared/global artifacts: a separate change.
- **After merge**: a new follow-up change, never reopening an archived one.

## Initiatives (complex work split into linked changes)

Split before creating a change when Propose's classification reads blast
radius or dependency impact beyond the project, when the request touches
more than one independent area, needs more than ~8 tasks, or contains
parts that could merge independently — independently-mergeable parts, not merely
independently-implementable ones: that is what units (Apply, step 4) are
for *within* one change, and an initiative is for parts that cross a Gate
2 of their own. Record an initiative
(`scripts/run-change initiative init|set --store <slug> --name <name>
title ... request ... children a,b,c` →
`<store>/.orchestration/initiatives/<name>.yaml`, plus `critique_rounds`
and `last_critique_result` for its critique loop, and `merged` — a
`child=sha` map filled in by `initiative merged` as each child lands)
instead of inferring the split later. `children` is ordered: it is the
intended merge order, and a child may only precede another it does not
depend on. Per-child `depends_on` lives on each child's own state file;
the initiative's order must be consistent with those edges, which the
critique checks.

- A child starts only when its dependencies are merged, up to the
  concurrency cap, and only after the disjoint-files check below clears it
  against every other in-flight child for that project.
- Gate 2 is per child by default. The first Gate 2 of an initiative may
  offer "approve this merge and let remaining green children merge
  autonomously." Gate 0 and Gate 1 always ask, per child — Gate 0's
  short-resume acceptance is never batched across children, even when a
  later Gate 2 is.
- `scripts/run-change status` shows the initiative tree — critique rounds
  and result, then each child in merge order with its phase and blocker,
  `not-started` if it has no state file yet, or `merged <sha>` once its
  commit is on the record.
- **Gates are orchestrator-owned.** Whether a child runs as a separate
  resumed session or as a subagent dispatched live by one orchestrator
  session, only the orchestrator talks to the human. A child that hits a
  Gate 0, Gate 1, or Gate 2 condition escalates (resume/finding, phase,
  gate log, diffstat, verify report as applicable) up to the orchestrator
  and stops; it never
  prompts the human itself. This keeps N concurrent children from producing
  N uncoordinated interruptions and preserves the single-voice approval
  flow the gates are built around.

Every lifecycle commit (on the target project) carries trailers: `Change:`,
`Initiative:`, `Depends-On:` (repeated), `Session:` — including the
squash-merge commit, so `git log` in the target project reconstructs
provenance even after the change's own artifacts are archived.

## Checker loops

Both generator/checker pairs — proposer/critic and implementer/Verify —
follow the same four rules. They are what keeps two agents from grading
each other forever.

- **Severity is binary.** Every finding is `blocking` (the output fails
  the standard it is judged against: a requirement the code does not meet,
  a seam that names a wrong file, a part of the request the spec skips, an
  implementation approach the checker cannot see how to verify or sees a
  concrete way to fail) or
  `warning` (the output is correct but violates the hard rule at the end
  of this doc, or leaves the store's `config.yaml` behind a convention or
  `orchestration.*` key the change introduced). The mechanism finding is never advisory, and its remedy is
  the fix the checker can name. The checker assigns severity; the fixer
  does not reclassify.
- **Pass is defined up front.** A change passes Verify when the full gate
  is green and the report has zero blocking findings. A draft passes
  critique when the report has zero blocking findings. Warnings never
  block a pass and never start a round: under `lifecycle: full` they get
  one mechanical sweep and move on; under `lifecycle: light` the sweep is
  skipped and the pass goes straight to the manual-task check. Without
  this line a loop spends its whole budget on comment style.
- **Budget, and convergence inside it.** Fix rounds cap at 3 per change,
  critique rounds at 2, then Gate 1. But the budget is a ceiling, not a
  target: a round is *converging* only if no finding the prior report
  marked closed reappears, and the blocking count is strictly lower than
  the prior round's. Either failing means the pair is not moving toward
  agreement — gate immediately with both reports, regardless of rounds
  left. Spending the remainder would only produce a third report saying
  the same thing. The count half is mechanical: `next` compares
  `last_*_result` with `prev_*_result` and returns `gate1` when a
  `blocking` count fails to fall. The reopened-finding half needs
  finding ids the reports don't carry, so the checker states it in the
  report and the orchestrator acts on it. The unit critic (Apply, step 4)
  is a third generator/checker pair but is not bounded by `propose_rounds`
  or `fix_attempts`: a `blocking` unit critique sends the same worker back
  for `unit-revise` under the unit's own `UNIT_ITER_CAP` (5), the cap
  already in force for that unit's iterate loop, not a separate round
  counter.
- **Unconditional, by design.** The pattern is usually reserved for
  changes worth a senior review. Here it runs on every change, because in
  autonomous mode nobody reads the diff before Gate 2 — the human's read of
  the spec at Gate 0 is a short resume by default, not a line-by-line
  review — so the checker *is* the senior review, not an addition to it.
  Cost is controlled
  by the tier (a `standard` model, one pass when the output is right) and
  by the pass line above, not by skipping the check.

### Critique beyond the spec

Wherever a deep-tier model generates an artifact, a `max`-tier model
critiques it before anything is built on it. The delta spec is one case;
the others:

- **Initiative records** (`<store>/.orchestration/initiatives/<name>.yaml`).
  Standards: the children together cover the request and nothing more;
  `depends_on` is acyclic, every edge is real (the child cannot start
  without it), and the `children` order respects every edge; no two children that could run concurrently share a file
  in their seam lists — a miss here surfaces as a merge conflict several
  hours later; each child is small enough to be a single change. Log the
  author's session entry under the initiative's name (`session append
  --name <initiative> phase proposed`), so `model critic --name
  <initiative>` resolves the tier above without new machinery. Rounds
  and the last result live on the initiative record (`scripts/run-change
  initiative set --store <slug> --name <initiative> critique_rounds <n>
  last_critique_result <value>`), cap 2, same values as a change's
  critique. The report goes to
  `<store>/.orchestration/initiatives/<name>.critique.md`.
- **Design docs** written at the deep tier during Propose. Same critic,
  logged under the owning change, standards: fidelity to the request,
  every decision names the alternative it rejected and why, nothing the
  spec will not need.

Same fresh-context rule, same report shape (what is wrong, what would
satisfy it, severity), same 2-round cap and convergence test.

## Model/effort routing

Pick a tier per task, not per session:

- `none`: workspace create/remove, running the gate, merge lane, state/
  initiative bookkeeping, commit trailers, archival file moves, `apply`
  itself, `units single`, and `unit merge` (the rebase/fast-forward/tick is
  deterministic bash; an agent is dispatched only for `merge-conflict`).
- `mechanical`: lint/format fixes, type-annotation-only fixes, deleting
  dead code and unused dependencies the gate's dead-code pass names,
  commit message drafting, first-round red-gate triage (flake vs lint vs
  type vs dead code vs logic).
- `standard`: ordinary implementation tasks, tests, a leaf unit worker
  (no other unit depends on it — see **Unit workers**), fix rounds 1 and 2
  that do not touch the spec, the merge-conflict agent, and — under
  `lifecycle: light` only — Propose and `revise` (the critic still
  resolves one tier above, to `deep`, via the generator/checker split
  below).
- `deep`: Propose (drafting the delta spec and seam list, every
  `full`-lifecycle change, not just initiative decomposition — `light`
  drafts at `standard`), `split` under `full` parallel mode (the unit
  generator), a foundation unit worker (two or more units depend on it), design
  docs, anything touching an invariant, fix round 3, any fix round after
  `spec_amend accepted`, Verify of a `standard` implementer, and the unit
  critic over a `standard` leaf worker.
- `max`: the strongest model available. Never a task tier: it is reached
  only as the checker of a `deep` generator — the critic of every Propose,
  Verify after a deep fix round, and the unit critic over a `deep`
  foundation worker. A unit critic is sized against *its unit's worker*
  (`model critic --unit <u>`), never the proposer: a `standard` leaf is
  reviewed at `deep`, and only a `deep` foundation unit reaches `max`.
  Costed per unit, not per change: a split into several concurrent units
  multiplies the critic calls by the unit count.

Why these placements: measured against a four-unit change, the two
serial, design-heavy tasks (the foundation unit and a spec-amending fix
round) were the ones that needed an extra review loop at `standard`, and
the top-tier critic spent three of five unit reviews finding nothing on
small leaf units. The leaf units themselves went green first time at
`standard`.

Specify/Plan (Propose) and Execute (Apply) are handled by the tiers above.
The checkers — Propose's critic, the unit critic, and Verify — are
different: they aren't sized by how hard the check is, but by who produced
the thing being checked. **The checker must be a different reader from
the generator: a different model, or the same model under a different
configuration.** A model is a weak reviewer of its own output, and a
weaker model is a weak reviewer of a stronger one's. The default way to
get a different reader is the tier one above the generator's, up the
ladder `mechanical < standard < deep < max`: a `standard` implementer is
verified at `deep`, a `deep` proposer is critiqued at `max`. Only when the
generator already sits at `max`, where nothing stronger exists, does the
tier one below (`deep`, the second strongest) review instead. If the
store's `model_*` config maps that neighbouring tier onto the generator's
own model, the command errors — unless the store sets
`orchestration.checker_effort` (e.g. `high`): then the same model is
accepted as the checker, and `model verify|critic` and `next` print an
`effort:` line after the model for the dispatch to apply. The different
configuration is what separates the two reads in that case — the fresh
context and the input contract below, which every checker gets, plus the
higher effort. Hosts whose agent dispatch cannot set effort per agent
(Claude Code's Agent tool today) should leave `checker_effort` unset and
keep distinct models. The generator's tier is read from its session
entry (`tier=` on the last `applying`/`checking` entry for Verify, the
last `proposed` entry for the critic); an entry without a tier is inferred
from its model against the tier table, and with no history at all the
implementer is assumed `standard` and the proposer `deep`.
`scripts/run-change model verify|critic --store <slug> --name <change>`
apply this rule; `next` reports the resulting tier and model on its
`critique` and `verify` actions. Use these commands' output for the
checker steps, not `model get` directly. Both checkers run in a fresh
context under the **checker input contract**: critic = request, draft,
seam list, prior report; Verify = proposal, seam list, branch diff, prior
report — never the generator's transcript, and never "explore the
codebase" beyond confirming a seam or a dependency claim. `model
verify`/`model critic` print the bare model id on line 1, then this
contract as static `input:` lines (`checker_inputs` in `scripts/lib.sh` —
it reads no file; it names the `seams` field rather than resolving it). A
caller that wants only the id pipes the output through `| head -n1`.

Each tier maps to a concrete model, resolved via `scripts/run-change model
get --store <slug> --tier <tier>` — the store's `openspec/config.yaml`
(`orchestration.model_mechanical` / `model_standard` / `model_deep` /
`model_max`) if
set, else the engine's default table (`model_for_tier` in
`scripts/lib.sh`):

| tier         | default model               |
|--------------|------------------------------|
| `mechanical` | `claude-haiku-4-5-20251001` |
| `standard`   | `claude-sonnet-5`           |
| `deep`       | `claude-opus-5`             |
| `max`        | `claude-fable-5-1`          |

`none` runs no model — it's plain bash bookkeeping (`scripts/run-change`
itself), never a task dispatched to an agent.

Pick the smallest tier that can be wrong safely.

Two host-level levers sit outside the tier table. **Fast mode** applies to
the `deep` model only (Claude Code serves Opus with faster output; Sonnet
and Haiku have no fast mode) and is a session setting, not a per-agent
one: enable it on the orchestrator session and every `deep` dispatch —
proposer, foundation workers, Verify, spec-amending fixers — inherits it.
**Prompt cache TTL**: a checker resumed after a human gate (Gate 1 in the
middle of Verify) re-warms its whole context when the 5-minute cache has
expired; the 1-hour TTL, where the host offers it, removes that cost.

### Project-skill stage mapping (Propose / critique / Verify)

Before dispatching Propose, the critique step, or Verify at the tier/model above, check
whether the project has named one of its own skills for that stage:
`scripts/run-change stage-skills get --store <slug> --stage plan|critic|test`. Output is
one skill name per line, empty if the project set nothing — see
[`docs/proposals/skill-stage-mapping.md`](https://github.com/soarea-viacom/openspec-orchestrator/blob/main/docs/proposals/skill-stage-mapping.md) for the
full design and why the mapping lives only in the resolved root's `openspec/config.yaml`
(`orchestration.stage_skills`), never in a skill's own frontmatter, and never behind any
other switch:

- **`plan`** — at most one name. If set, dispatch that skill (via the `Skill` tool, not a
  bare model call) to draft the delta spec and seam list **instead of** the deep-tier
  model — this *replaces* the default drafter, it does not add to it. If unset, Propose
  runs exactly as described in Phases step 3: deep tier, no skill involved.
- **`critic`** — zero or more names. If non-empty, dispatch every listed skill **in
  addition to** the tier/model critic already described in Phases step 3 — never instead
  of it. The critique step only passes if *none* of them — built-in or mapped — reports a
  blocking finding; merge every mapped skill's findings into the one critique report,
  each tagged with which skill produced it, same file, same `last_critique_result`
  handling as today.
- **`test`** — zero or more names. Same rule as `critic`, stacked on top of the tier/model
  Verify checker described in Phases step 6, merged into the one verify report the same
  way.

Two things this mapping does not do, on purpose: it never disables the built-in
checker for `critic`/`test` (a mapped skill is additional signal, not a replacement for
the one check this engine can vouch for itself), and it never checks whether a mapped
skill is safe to run unattended — if a project maps a skill that stops to interview a
human, the change simply stalls in that phase, visible the same way any other broken step
is, not something this engine detects in advance.

### Role overlays (project notes for a role, kept in the store)

The engine's role prompts — proposer, critic, unit worker, unit critic,
Verify — are the same for every project. What differs per project is
knowledge: how to run and read its tests, a review checklist tuned to its
failure modes, the harness a UI unit must use. A store carries that as
**role overlays**: `<store>/openspec/roles/<role>.md`, one file per role
from the fixed set `proposer`, `critic`, `worker`, `unit-critic`,
`verifier`, beside `config.yaml` so it versions with the specs and, in
external mode, never touches the target project. `next` prints
`overlay: <path>` on every action that dispatches that role (and
`also_overlay:` for the Verify it runs beside `check`); `scripts/run-change
roles get --store <slug> --role <role>` prints the text, empty when the
store has none, and refuses a role outside the set. The orchestrator
appends the text verbatim to the dispatch, after the engine's own
instructions for that role.

The engine's own instructions for a role are literal text at
`scripts/roles/<role>.md`, printed before the overlay: `next` prints
`prompt: <path>` (and `also_prompt:` for the Verify beside `check`)
immediately before any `overlay:`/`also_overlay:` line, and
`scripts/run-change roles prompt --store <slug> --role <role>` prints the
engine prompt text, then — when the store has one — a blank line and the
overlay text, engine prompt always first. The dispatch for a role is the
engine prompt, then the overlay, then the checker's `input:` lines (for
proposer and worker, the task's own material).

An overlay adds; it never overrides. The input contract, the session log
shapes, the iterate loop, the pass line, and the tier the role runs at are
the engine's, and where overlay text contradicts them the engine's text
wins — the overlay is project knowledge handed to a role, not a
replacement role. `worker` covers every writing dispatch: unit workers,
fix rounds, the mechanical sweep, the merge-conflict agent, and `split`.
The orchestrator's own session is not a role and takes no overlay.

### Fix rounds

One loop serves both a red full gate (step 5) and a non-clean Verify
(step 6): a fixer at the implementer tier receives the failure or the
verify report — never the checker's transcript — and changes only what the
findings name. `fix_attempts` counts both kinds against the same cap of 3
per change; a change does not get three rounds for tests and three more
for review, and a round that fails the convergence test under **Checker
loops** gates at once. Escalation is by round number: round 1 mechanical/standard by
triage, round 2 standard, round 3 deep, then Gate 1. Each fixer logs a
session entry with `phase checking` before Verify reruns, so `model verify`
sees the fixer as the latest implementer and picks the tier above it to
re-check its work (a round-3 `deep` fixer is verified at `max`). A worker that fails its own check once retries one tier
up before it counts as a fix round — but before failing, it may ask an
advisor (below). Record
`model` and `tier` on every session-history entry — resolve the model with
`model get` first, then `scripts/run-change session append --store <slug>
--name <change> role worker phase applying tier mechanical model
<model-id> transcript_id <id>` — so `session list` gives the full history
and `status` surfaces each change's most recent tier in a `LAST_TIER`
column, to catch when a change burned expensive calls on mechanical work.

### Advisor: the deep tier for one question, not the whole task

Most of a `standard` or `mechanical` task is routine; the hard part, when
there is one, is a slice — a design fork, a subtle bug, a piece of logic
the worker keeps getting wrong. Re-running the whole task at `deep` pays
top-tier prices for the routine part too. Instead a stuck worker packages
the one question and hands it to an **advisor**: a subagent at the `deep`
tier, fresh context, given the question, the proposal, and the file paths
it needs — never the worker's transcript. The advisor is read-only. It
returns an answer (a decision and why, or a diagnosis and the fix to make);
the worker applies it and carries on. The call is obtained, never
assumed: `scripts/run-change advisor request --store <slug> --name
<change> --worker <transcript-id>` checks both caps below, logs the entry
(`role advisor tier deep for=<worker>`) and prints the model to dispatch.
A direct `session append` with `role advisor` is refused, so the log
cannot show a call the engine did not grant.

Bounds, enforced by `advisor request`, because two agents cost more than
one when the hard part isn't rare:

- **One advisor call per worker task.** A second request from the same
  worker is refused: the task is not routine — return, and the
  orchestrator re-dispatches the whole task one tier up, as with a failed
  self-check.
- **Two advisor calls per change** across all its workers — `status` shows
  the count against the cap in its `ADVISOR` column, read from the
  session log. A third request is refused: the change was mis-tiered at
  Propose; note it in the verify report so the next Propose for that area
  starts at `standard` or `deep` outright.
- **Never from `deep`**, and never from a checker: Verify and the critic
  are already the strong read of the work, and an advisor that advises
  the checker collapses the generator/checker split.
- **Ask before failing, not instead of checking.** The self-check and the
  gate still run on the advised code; the advisor's answer is one more
  input a fresh reader can verify, not an approval.

### Coordination: blackboard only, no messaging

Workers report to the orchestrator and never to each other. Everything an
agent needs from another agent it reads from a file the orchestrator owns
— the proposal, the seam list, the change's state, the verify or critique
report. Those files are the blackboard, and they are enough because
concurrent workers are on disjoint seams by construction: a cross-seam
need that surfaces mid-run is a seam-list finding for the orchestrator,
not a note for a sibling. There is no worker-to-worker messaging and no
shared scratch file between concurrent workers. Both would let a wrong
guess in one context spread to another without passing through a
checkable artifact, which is exactly what **Isolation** exists to prevent.

## Hard rule: written for agents

- Comments exist only to help a later agent act correctly: a constraint the
  code can't show, the requirement ID a block satisfies, why the obvious
  alternative is wrong, an external quirk, a boundary invariant. Forbidden:
  narrating the next line, restating a name, tutorial explanations,
  decorative headers, docstrings repeating the signature.
- Keep it simple: one script/function that does the job beats a framework;
  no abstraction with a single caller.
- Keep it short: the shortest artifact, rule, commit message, gate summary,
  or reply that is complete.
- Exception: inside agent-facing dispatch text (`scripts/roles/*.md`),
  anchor repetition wins and is not deduplicated; human-facing prose keeps
  the terseness rule above.
- Leave nothing abandoned: a replaced approach, a helper refactored past,
  a dependency pulled in for a dropped idea — delete it in the same
  change. The full gate's dead-code pass is what enforces this; a worker
  that "might need it later" is wrong, because a later change can add it
  back from git history.
- Verify reports human-narrative comments and oversized artifacts as
  findings; the fix round for them runs at the mechanical tier.
- Build seconds-long test artifacts — a compiled binary, a bundled app, a
  container image, anything that takes real time — once per test run into
  a shared fixture (a `before`/global/session hook), never rebuilt per
  test or per file. Verify reports a per-test or per-file rebuild as a
  warning.
