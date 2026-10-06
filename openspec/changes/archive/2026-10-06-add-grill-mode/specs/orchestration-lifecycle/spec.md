## MODIFIED Requirements

### Requirement: Checker input contract
`model critic` and `model verify` SHALL print the bare model id on the first line, followed by static `input:` lines (they read no state file; the seam list is named as the `seams` field, not resolved) listing the checker's inputs (critic: request, draft, seam list, Project glossary, ADRs, prior report; Verify: proposal, seam list, branch diff, prior report) and the rule that other files are read only to confirm a seam or a dependency claim, never to explore the codebase. The critic's Project glossary line SHALL name `<store>/openspec/CONTEXT.md` (the store root's path, not the change worktree's) as read if present, with a non-canonical term one warning finding; its ADR line SHALL name `<store>/openspec/adr/` as read if present, with a proposal contradicting an ADR blocking unless it names the ADR it supersedes. `model critic --unit <u>` SHALL print the same model id as `model critic`, followed by the unit-critic `input:` lines: proposal and delta spec, the unit's files and task ids, the unit diff from its `base`, the checks diff to its `checks_commit`, its screenshots as listed by `units ready-for-review` and opened with an image-capable read, and the prior unit critique, plus the same rule line. Neither `model verify` nor `model critic --unit <u>` SHALL print the Project glossary or ADR lines.

#### Scenario: Contract emitted
- **WHEN** `model verify` runs for a change with history
- **THEN** line 1 is exactly the checker model id and later lines include `input:` and `seam`

#### Scenario: Contract for an initiative critic
- **WHEN** `model critic --name <initiative>` runs for an initiative that has a `proposed` session entry and no change state file
- **THEN** it prints the model id followed by the `input:` lines

#### Scenario: Unit-critic contract
- **WHEN** `model critic --name <change> --unit ui` runs
- **THEN** line 1 equals line 1 of `model critic --name <change>`, and later lines include `input:`, `screenshot`, and `checks_commit`

#### Scenario: Critic reads the Project glossary and ADRs
- **WHEN** `model critic --store teststore --name feat-critic` runs
- **THEN** it prints a line starting `input: the Project glossary` containing `<teststore root>/openspec/CONTEXT.md` and a line starting `input: the ADRs` containing `<teststore root>/openspec/adr/` and `supersedes`, both after the seam line and before `input: the prior critic report, if any`

#### Scenario: Verify and unit-critic unchanged
- **WHEN** `model verify` and `model critic --unit <u>` run
- **THEN** neither output contains `openspec/CONTEXT.md` or `openspec/adr/`

## ADDED Requirements

### Requirement: Critique paragraph names the glossary inputs
AUTONOMOUS-ORCHESTRATION.md's Phases step 3 **Critique** paragraph SHALL list the store's Project glossary (`openspec/CONTEXT.md`) and ADRs (`openspec/adr/`), when present, in the critic's input contract, with the same grading rule as the `input:` lines.

#### Scenario: Doc lists the inputs
- **WHEN** `tests/run.sh` reads AUTONOMOUS-ORCHESTRATION.md from the line containing `**Critique**` to the line containing `The critic writes a **critique report**`
- **THEN** that range contains `openspec/CONTEXT.md` and `openspec/adr/`
