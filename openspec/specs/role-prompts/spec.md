# role-prompts Specification

## Purpose
Literal, stable engine dispatch text per role, carrying six repeated anchor phrases, so every fresh-context agent receives the same dispositions verbatim instead of the orchestrator's paraphrase.

## Requirements

### Requirement: Engine role prompt files
The engine SHALL ship exactly one prompt file per role in `ROLES` at `scripts/roles/<role>.md` (`proposer`, `critic`, `worker`, `unit-critic`, `verifier`) and no other file in that directory. Each file SHALL be at most 20 lines, have no Markdown heading, and quote its role's invariant strings verbatim: proposer `--store <slug>`, `seams "<seam>=<file>,<file>;<seam>=<file>"`, `openspec/CONTEXT.md`, `openspec/adr/` and `never edit`; critic `never the generator's transcript`, `openspec/CONTEXT.md`, `openspec/adr/`, `names the ADR it supersedes` and `non-canonical term`; verifier `never the generator's transcript`; worker `` `git add -- <files>`, never `-A` `` and `unit iterate`; unit-critic `never the generator's transcript` and `screenshot`.

#### Scenario: One file per role
- **WHEN** `tests/run.sh` lists `scripts/roles/`
- **THEN** it holds exactly `proposer.md`, `critic.md`, `worker.md`, `unit-critic.md`, `verifier.md`

#### Scenario: Short, headerless, invariants verbatim
- **WHEN** each prompt file is read
- **THEN** it has at most 20 lines, no line starting with `#`, and contains every invariant string listed for its role

#### Scenario: Glossary and ADR lines carry no anchor
- **WHEN** `tests/run.sh` counts anchors in `proposer.md` and `critic.md` after the glossary and ADR lines are added
- **THEN** every assigned anchor still occurs exactly twice, once on line 1 and once on the last line, and every unassigned anchor occurs 0 times

### Requirement: Anchor placement
The anchor set SHALL be exactly six phrases: `seam` (counted as a whole word outside an angle-bracket placeholder such as `<seam>`), `fresh read`, `generator/checker split`, `smallest tier that can be wrong safely`, `turns, not tokens`, `the engine records, the worker never asserts`. Each prompt SHALL contain each anchor assigned to its role exactly twice — once on its first line and once on its last line — and no anchor not assigned to it. Assignment: proposer `seam`, `generator/checker split`, `smallest tier that can be wrong safely`, `turns, not tokens`; critic `fresh read`, `generator/checker split`, `seam`, `turns, not tokens`; worker `seam`, `the engine records, the worker never asserts`, `turns, not tokens`; unit-critic `fresh read`, `generator/checker split`, `the engine records, the worker never asserts`, `turns, not tokens`; verifier `fresh read`, `generator/checker split`, `seam`, `the engine records, the worker never asserts`, `turns, not tokens`.

#### Scenario: Assigned anchors twice, first and last line
- **WHEN** `tests/run.sh` counts each anchor in each prompt file
- **THEN** every assigned anchor occurs exactly twice, once on line 1 and once on the last line

#### Scenario: Unassigned anchors absent
- **WHEN** `tests/run.sh` counts an anchor not assigned to a role in that role's file
- **THEN** the count is 0

### Requirement: Roles prompt subcommand
`run-change roles prompt --store <slug> --role <role>` SHALL print the engine prompt for that role and, when the store has an overlay for it, one blank line followed by the overlay text, so the engine prompt always precedes the overlay. It SHALL exit non-zero naming the role set for a role outside `ROLES`, and `roles get` output SHALL be unchanged.

#### Scenario: Engine prompt without overlay
- **WHEN** `roles prompt --role verifier` runs against the test store before any file under its `openspec/roles/` exists
- **THEN** it exits 0 and its output equals the contents of `scripts/roles/verifier.md`

#### Scenario: Engine prompt before overlay
- **WHEN** the store has `openspec/roles/critic.md` and `roles prompt --role critic` runs
- **THEN** the engine prompt's last line appears before the overlay's first line, and `roles get --role critic` still prints only the overlay text

#### Scenario: Unknown role refused
- **WHEN** `roles prompt --role reviewer` runs
- **THEN** it exits non-zero with `unknown role` in its output

### Requirement: Next surfaces the engine prompt
On every action `role_for_action` maps to a role, `next` SHALL print `prompt: <absolute engine path>/scripts/roles/<role>.md` immediately after `reason:` and before any `overlay:` line; on `check` it SHALL print `also_prompt:` with the verifier prompt path immediately after `also_model:` and before any `also_overlay:` line. Actions without a role SHALL print neither. Every line `next` printed before this change SHALL keep its text and relative order.

#### Scenario: Prompt line before overlay
- **WHEN** a change is at `proposed` with a draft logged and no critique, and the store has a critic overlay
- **THEN** `next` prints `prompt: <engine>/scripts/roles/critic.md` on the line after `reason:` and the `overlay:` line follows it

#### Scenario: Prompt without overlay
- **WHEN** a fresh change has no draft and the store has no `openspec/roles/proposer.md`
- **THEN** `next` prints `action: propose`, `prompt: <engine>/scripts/roles/proposer.md`, and no `overlay:` line

#### Scenario: Concurrent Verify prompt
- **WHEN** a change is at `checking` with no gate result
- **THEN** `next` prints `also_prompt: <engine>/scripts/roles/verifier.md` after `also_model:`

#### Scenario: None-tier action
- **WHEN** `next` returns `tasks-open`
- **THEN** its output contains no `prompt:` line

### Requirement: Style split documented
AUTONOMOUS-ORCHESTRATION.md SHALL state that anchor repetition wins inside agent-facing dispatch text and terseness wins in human-facing prose, and that the dispatch for a role is the engine prompt, then the overlay, then the task's own inputs. CONTEXT.md SHALL define **Role prompt** and **Anchor**, and the store's `openspec/config.yaml` `context:` block SHALL name `scripts/roles/<role>.md`.

#### Scenario: Doc states the split and the order
- **WHEN** `grep -n 'scripts/roles' AUTONOMOUS-ORCHESTRATION.md` runs
- **THEN** it hits a line in the **Hard rule: written for agents** section (the style split, repeated anchors not deduplicated) and a line in the **Role overlays** section (engine prompt via `prompt:` / `roles prompt` precedes the overlay)

#### Scenario: Vocabulary and context updated
- **WHEN** `grep -n -E '\*\*(Role prompt|Anchor)\*\*' CONTEXT.md` and `grep -n 'scripts/roles/<role>.md' openspec/config.yaml` run
- **THEN** both CONTEXT.md entries are found, the **Anchor** entry contains all six anchor literals, and the `config.yaml` hit lies inside the `context:` block
