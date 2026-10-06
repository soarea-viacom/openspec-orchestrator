# Design

`<root>` = the resolved artifact root (Step 1): the project in local mode, `~/.local/share/openspec/stores/<slug>` in external mode — what `store_path <slug>` returns. `<project>` = the target project's main checkout.

### D1. Grill mode is SKILL.md prose, not an engine subcommand

- Grill mode precedes a change: there is no change name, state file, slot or worktree, so nothing for `next` to decide. It is a `## Grill mode` section in SKILL.md, placed after **Autonomous only** and before **Optional convenience**, run by the orchestrator like Gate 0's presentation rules are.
- Invocation: the skill invoked with a request that asks to grill a plan or idea before a change, e.g. `/openspec-orchestrator grill how should we approach rate limiting?`. A request to implement something is a change, never grill mode.
- Sequence the section states, in order: Step 0 checks 1–3 → Steps 1–2 (root resolved; check 4, the trunk preflight, is not run — it gates opening a change) → external-mode snapshot (D3) → first round (D2) → interview (D4) → external-mode compare (D3) → handoff (D6).
- Rejected: `run-change grill snapshot|check` — a CLI surface and state for one `git status --porcelain` comparison the orchestrator can run directly; the Guardrails line forbids a new subcommand.
- Rejected: keeping `/sdd:explore` beside grill mode — the request replaces it; grill mode's first round is the explore analysis, so nothing is lost.

### D2. First round = explore's analysis

- Read the relevant code boundaries, existing specs (`openspec list --store <slug>`, `openspec spec … --store <slug>`) and active changes; present two or three approaches with trade-offs, risks and a recommendation. This round writes nothing.
- The human may stop after it. With no term or decision resolved, nothing is written: domain-modeling creates files lazily, so the stop needs no special case.

### D3. External-mode guard

- External mode only: in local mode the glossary and ADRs land under the project's own `openspec/` by design, so the project's status is expected to change there.
- Before the first round: `git -C <project> status --porcelain` → kept in the conversation (no file written). After the last round, before the handoff: run it again and compare byte for byte. Different → stop, show the human the lines that differ, and make no handoff and no offer to start a change.
- The section quotes the command literally (`git status --porcelain`) so the doc check can find it.

### D4. Interview: two skills, explicit root

- The orchestrator calls the Skill tool for `grilling` and for `domain-modeling` itself. It never calls `grill-with-docs`: that skill is `disable-model-invocation: true` and passes no root, and domain-modeling's default root is the repo's `CONTEXT.md` and `docs/adr/`, which in external mode is the project.
- The invocation tells domain-modeling: the **Project glossary** is `<root>/openspec/CONTEXT.md`; ADRs go in `<root>/openspec/adr/`; the target project's own root `CONTEXT.md` and `docs/adr/`, if present, are vocabulary to read, never files to write. Same relative path (`openspec/CONTEXT.md`, `openspec/adr/`) in both modes, so the proposer and critic look in one place.
- The engine's own `skills/openspec-orchestrator/CONTEXT.md` is a different file (the engine glossary); the Project glossary never lives under the skill directory.
- Missing skills, judged from the host's available-skill list, degrade with no message: no `domain-modeling` → interview, no glossary or ADR writes; no `grilling` → the orchestrator's own inline rounds (numbered questions, a recommended answer each, wait for answers); neither → inline rounds, no writes.

### D5. Consumers: critic `input:` lines and two prompt lines

- `checker_inputs critic` prints, after the seam line and before the prior-report line (exact text, `%s` = `store_path <slug>`):
  - `input: the Project glossary, if present — %s/openspec/CONTEXT.md: a non-canonical term is one warning finding`
  - `input: the ADRs, if present — %s/openspec/adr/: a proposal contradicting an ADR is blocking unless it names the ADR it supersedes`
- Store-root paths, not the change worktree: grill-mode writes are uncommitted in `<root>`, and a worktree checked out from trunk does not carry them. `checker_inputs` still reads no file — "if present" leaves the existence check to the critic. The initiative critic gets the same lines (same branch). Verify and unit-critic branches are untouched.
- `scripts/roles/proposer.md` gains one body line (10 lines total): ``Read the Project glossary `<store>/openspec/CONTEXT.md` and the ADRs in `<store>/openspec/adr/` when present: use their canonical terms, name any ADR the proposal supersedes, and never edit either; only grill mode writes them.``
- `scripts/roles/critic.md` gains one body line after the five-standards line (11 lines total): ``When present, grade against the Project glossary `<store>/openspec/CONTEXT.md` and the ADRs in `<store>/openspec/adr/` (your `input:` lines): a proposal contradicting an ADR is `blocking` unless it names the ADR it supersedes; a non-canonical term is a `warning`.``
- Neither line contains any of the six anchors, so the anchor counts and line-1/last-line placement are unchanged.

### D6. No commit; handoff

- Grill mode never commits and never runs a git command that writes; its glossary and ADR writes stay uncommitted, like every other root artifact.
- The session ends with a sharpened request summary (the request restated in the glossary's canonical terms, naming any ADR written) and an offer to start the change with it — starting means invoking the full run with that summary as the request. No offer when the D3 guard tripped.

### D7. Writers and vocabulary

- SKILL.md **Guardrails** gains one bullet: only grill mode writes the Project glossary and ADRs; Propose and Archive may cite an ADR or name the one a proposal supersedes, never edit either.
- SKILL.md frontmatter `description` and `atlas-catalog.json` `description` become, identically: the current text with `invokes /sdd:explore for read-only discovery` replaced by `wants to grill a plan before a change (grill mode — weigh approaches, then sharpen terms and decisions into the Project glossary and ADRs)`. The SKILL.md value is an unquoted plain YAML scalar, so it MUST contain no `: ` and no ` #` (either stops the frontmatter parsing); it stays unquoted so the bytes match the catalog string. No double quote or backslash, so the JSON string needs no escaping. Edited in place; the catalog file is not re-serialized.
- **Autonomous only**'s last sentences become: the only invocation that is not a full run is grill mode, which precedes a change and is not a phase of one; Gate 0 stays the only pause inside a change.
- CONTEXT.md gains **Project glossary** (`<root>/openspec/CONTEXT.md` plus ADRs in `<root>/openspec/adr/`; distinct from this engine glossary; written only by grill mode; read by proposer and critic) and **Grill mode** (the one pre-change mode; D1–D6 in two or three lines); **Checker input contract**'s critic list becomes "request, draft, seam list, Project glossary, ADRs, prior report".
- AUTONOMOUS-ORCHESTRATION.md Phases step 3 **Critique** paragraph enumerates the critic's input contract, so its list gains "the store's Project glossary (`openspec/CONTEXT.md`) and ADRs (`openspec/adr/`) when present", with the D5 grading rule. Leaving it would contradict `model critic`'s output. No other paragraph changes.
- `openspec/config.yaml` `context:` gains one sentence: grill mode (SKILL.md) is the only pre-change mode and the only writer of a root's Project glossary (`openspec/CONTEXT.md`) and ADRs (`openspec/adr/`); the proposer and critic read them. Verify's config-drift input then sees the convention reflected.
- README: the Usage `/sdd:explore` block becomes `/openspec-orchestrator grill how should we approach rate limiting?` with a one-line lead-in; the layout table's `CONTEXT.md` row adds that a target project's Project glossary lives at `<root>/openspec/CONTEXT.md`.

### D8. Checks

All new checks go in `tests/run.sh`, using `check`/`check_out` and section ranges (heading line to the next `^## ` line), as the existing role-prompt doc checks do:

- `model critic --name feat-critic`: a line starting `input: the Project glossary` containing `$STORE/openspec/CONTEXT.md`, a line starting `input: the ADRs` containing `$STORE/openspec/adr/`, both on line numbers below the seam line and above `input: the prior critic report`. `model verify --name feat-verify` and `model critic --store storeu3 --name feat-owner --unit a`: no `openspec/CONTEXT.md`, no `openspec/adr/`.
- `ROLE_INVARIANTS` gains the strings in the role-prompts delta; existing anchor and 20-line checks stay unedited and green.
- SKILL.md: `grep -c '/sdd:explore'` = 0 in SKILL.md, README.md, atlas-catalog.json; exactly one `^## Grill mode$`; the section contains each of `Step 0`, `grilling`, `domain-modeling`, `<root>/openspec/CONTEXT.md`, `<root>/openspec/adr/`, `docs/adr/`, `git status --porcelain`, `two or three approaches`, `no message`, `uncommitted`, `sharpened request`, `Gate 0`; SKILL.md contains no `grill-with-docs`; the **Autonomous only** section contains `grill mode`; the **Guardrails** section contains `Project glossary` and `grill mode`.
- Description: `sed -n 's/^description: //p'` of SKILL.md equals the `"description"` string of atlas-catalog.json, and contains `grill mode`; the SKILL.md `description:` line contains exactly one `: ` (the key's) and no ` #`.
- CONTEXT.md has `**Project glossary**` and `**Grill mode**`; the **Checker input contract** entry (extracted as the Anchor entry is) contains `Project glossary`. `openspec/config.yaml` has `openspec/CONTEXT.md` inside the `context:` block. README contains `/openspec-orchestrator grill` and its `CONTEXT.md` layout row contains `openspec/CONTEXT.md`. AUTONOMOUS-ORCHESTRATION.md lines between `**Critique**` and `The critic writes a **critique report**` contain `openspec/CONTEXT.md` and `openspec/adr/`.
- The interview itself (skills invoked, guard compared, nothing committed) runs in a human session and has no CLI to drive; the doc checks above are its proxy, the same standard the existing Gate 0 and light-lifecycle doc rules use.
