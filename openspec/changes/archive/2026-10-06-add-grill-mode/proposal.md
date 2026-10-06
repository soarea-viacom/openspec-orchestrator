# Proposal

## Why

`/sdd:explore` is the only pre-change mode and writes nothing, so the terms and decisions a discovery session settles are gone by the time Propose drafts, and the critic has nothing to grade a proposal's vocabulary or prior decisions against. Grill mode keeps explore's analysis as its first round, then interviews the human with the `grilling` and `domain-modeling` skills and records resolved terms in a **Project glossary** (`<root>/openspec/CONTEXT.md`) and decisions as ADRs (`<root>/openspec/adr/`). The proposer and the critic read both. Gate 0 stays the only pause inside a change; grill mode runs before one.

## Classification

- **Scope:** several seams — SKILL.md (new Grill mode section, description, Autonomous only, Guardrails), `atlas-catalog.json`, README.md, CONTEXT.md, AUTONOMOUS-ORCHESTRATION.md (the Critique paragraph's input-contract sentence), `openspec/config.yaml` `context:`, the `critic` branch of `checker_inputs` in `scripts/lib.sh`, `scripts/roles/proposer.md` and `critic.md`, `tests/run.sh`, `releases.json` via `atlas bump`.
- **Blast radius:** callers inside the project plus the skill's trigger surface. `model critic` gains two additive `input:` lines the orchestrator already includes verbatim; Verify's and the unit-critic's lines are unchanged. The skill description (and the identical catalog description) drops `/sdd:explore` and names grill mode, which changes when the skill is picked. No `next` output, state field or `orchestration.*` key changes.
- **Novelty:** new logic — a pre-change interview mode that composes two third-party skills with an explicit root, an external-mode `git status --porcelain` guard, and silent degradation. The `checker_inputs` lines and role-prompt lines follow existing patterns.
- **Dependency impact:** no new package or tool. A soft runtime dependency on two user-installed skills (`grilling`, `domain-modeling`), each optional: absent, grill mode degrades without a message.

**Guardrails:** no new `run-change` subcommand, state field, `orchestration.*` key, role, or `stage_skills` change; no change to Verify's or the unit-critic's `input:` lines or to any `next` output; no vendored third-party skill and no use of `grill-with-docs`; no new pause inside a change (Gate 0 stays the only one); no write to a target project's root `CONTEXT.md` or `docs/adr/`, and in external mode no change to the project's `git status --porcelain`; no commit of grill-mode writes; no edit of the Project glossary or an ADR by Propose, the critic, Apply, Verify or Archive; no role prompt over 20 lines and no new anchor occurrence in a role prompt; no hand edit of `releases.json`.

Shape: `full` change (new logic and a changed trigger description; not fast-path).

## What Changes

1. **Grill mode replaces `/sdd:explore`.** SKILL.md gains a `## Grill mode` section; every `/sdd:explore` reference goes (description, Autonomous only). The frontmatter description and `atlas-catalog.json`'s description name grill mode and stay identical. README's `/sdd:explore` example becomes `/openspec-orchestrator grill …`.
2. **First round = explore's analysis.** Read the relevant code, specs and active changes; present two or three approaches with trade-offs and a recommendation. Stopping there with no term or decision resolved writes nothing.
3. **Run.** After Step 0 checks 1–3 and Steps 1–2 resolve the root, the orchestrator invokes `grilling` and `domain-modeling` itself, telling domain-modeling its glossary is `<root>/openspec/CONTEXT.md` and its ADRs go in `<root>/openspec/adr/` — the same relative path in both modes. A target project's own root `CONTEXT.md` / `docs/adr/` are read as vocabulary only.
4. **External-mode guard.** `git -C <project> status --porcelain` captured before the first round must be byte-identical after the session; otherwise stop and report the differing lines, with no handoff.
5. **Missing skills degrade silently.** No `domain-modeling` → interview without glossary/ADR writes; no `grilling` → the orchestrator's own inline rounds. No message either way.
6. **No commit; handoff.** Writes stay uncommitted. The session ends with a sharpened request summary and an offer to start the change with it.
7. **Consumers.** `checker_inputs critic` prints two new `input:` lines (Project glossary, ADRs — store-root paths, "if present", with the grading rule); `roles/proposer.md` and `roles/critic.md` each gain one line. Verify unchanged.
8. **Critic grading.** A proposal contradicting an ADR is `blocking` unless it names the ADR it supersedes; a non-canonical term is a `warning`.
9. **Writers.** Only grill mode edits the Project glossary and ADRs; Propose/Archive may cite an ADR or name a superseded one, never edit (SKILL.md Guardrails).
10. **Vocabulary.** CONTEXT.md gains **Project glossary** and **Grill mode**; **Checker input contract** names the two critic inputs. The `context:` block of `openspec/config.yaml`, README's layout table and AUTONOMOUS-ORCHESTRATION.md's Critique sentence stay consistent.
11. **Release.** One `atlas bump skill openspec-orchestrator --minor -m "..."` against `main`.

Non-goals: vendoring third-party skills; any `stage_skills` change; the user-level `~/.claude/commands/sdd/explore.md` file, which is outside this repo.

## Impact

- Affected code: `skills/openspec-orchestrator/scripts/lib.sh` (`checker_inputs`, critic branch only), `tests/run.sh`.
- Affected prompts: `skills/openspec-orchestrator/scripts/roles/proposer.md`, `critic.md`.
- Affected docs: `skills/openspec-orchestrator/SKILL.md`, `AUTONOMOUS-ORCHESTRATION.md`, `CONTEXT.md`, `README.md`, `atlas-catalog.json`, `openspec/config.yaml`; `releases.json` via `atlas bump`.
- New capability: `grill-mode`. Modified: `role-prompts` (Engine role prompt files), `orchestration-lifecycle` (Checker input contract).
