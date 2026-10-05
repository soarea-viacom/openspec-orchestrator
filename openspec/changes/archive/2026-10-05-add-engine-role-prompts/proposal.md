# Proposal

## Why

A worker, critic or Verify today receives `next`'s `reason:`, the checker `input:` lines, an optional `overlay:` path, and whatever the orchestrator paraphrases from AUTONOMOUS-ORCHESTRATION.md. There is no literal engine role prompt, so the dispositions the engine depends on (seam ownership, fresh reads, the generator/checker split, tier economy, batching, engine-recorded checks) reach each agent only as paraphrase. A short, stable prompt per role, carrying six anchor phrases from the project's own vocabulary, gives those dispositions a guaranteed, greppable carrier.

## Classification

- **Scope:** `scripts/lib.sh`, `scripts/run-change`, `tests/run.sh`, five new prompt files under `scripts/roles/`, and four docs; one new subcommand and two additive `next` lines.
- **Blast radius:** engine-internal; `next` gains `prompt:`/`also_prompt:` lines, every existing line keeps its text and relative order; overlays and target projects are untouched.
- **Novelty:** known pattern — mirrors role overlays (a path line from `next` plus a text-printing `roles` subcommand); the anchor convention is the only new idea.
- **Dependency impact:** none — no new dependency, no new `orchestration.*` key.

**Guardrails:** no new `orchestration.*` key; no change to overlay precedence or to `roles get` output; no change to any existing `next` output line or the order of existing lines; no prompt text inlined into `next` output or lib.sh; no rewording of existing invariants in the docs; no more than six anchors; no prompt over 20 lines; no anchor more than twice in a prompt; no new dependency.

Shape: `full` change (not fast-path: a new subcommand, new `next` output, and a new documented convention).

## What Changes

1. **Engine role prompts.** `scripts/roles/<role>.md` for each role in `ROLES` (`proposer`, `critic`, `worker`, `unit-critic`, `verifier`), ≤20 lines, versioned with the engine. Only the ceiling is enforced: the request's 10-line floor is dropped, since a prompt complete in fewer lines is right and padding it to a minimum would be the defect. Each carries its role's anchors on the first line and again on the last (exit/pass) line, and quotes the role's invariants verbatim from the docs.
2. **Six anchors.** `seam`, `fresh read`, `generator/checker split`, `smallest tier that can be wrong safely`, `turns, not tokens`, `the engine records, the worker never asserts`. Fixed per-role assignment (design D3).
3. **`roles prompt --store <slug> --role <r>`.** Prints the engine prompt, then the store's overlay (if any) after one blank line. Refuses a role outside `ROLES`. `roles get` is unchanged.
4. **`next` surfaces the prompt.** On every action with a role, `prompt: <engine>/scripts/roles/<role>.md` immediately before the existing `overlay:` line; on `check`, `also_prompt:` immediately before `also_overlay:`. None-tier actions print neither.
5. **Docs.** AUTONOMOUS-ORCHESTRATION.md (Role overlays → engine prompt first; Driving the loop; Unit workers; Hard rule gains the style split: anchor repetition wins in agent-facing dispatch text, terseness in human prose), SKILL.md Guardrails, CONTEXT.md (**Role prompt**, **Anchor**; **Role overlay**, **Next action** updated), `openspec/config.yaml` `context:`. Version bump via `atlas bump`.

## Impact

- Affected code: `scripts/lib.sh` (`role_prompt`, `emit_overlay` → `emit_role_lines`, `check` branch of `next_action`, header comment), `scripts/run-change` (`cmd_roles_prompt`, dispatch, usage), `tests/run.sh`.
- New files: `scripts/roles/{proposer,critic,worker,unit-critic,verifier}.md`.
- Affected docs: AUTONOMOUS-ORCHESTRATION.md, SKILL.md, CONTEXT.md, `openspec/config.yaml`, `releases.json` (via `atlas bump`).
- New capability: `role-prompts`. `orchestration-lifecycle` requirements are unchanged.
