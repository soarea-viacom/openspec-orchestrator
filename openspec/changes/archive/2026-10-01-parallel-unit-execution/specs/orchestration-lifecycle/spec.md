# Spec Delta

## MODIFIED Requirements

### Requirement: Lifecycle field
State init SHALL write `lifecycle: full`; a missing value SHALL read as `full`; any value other than `full` or `light` SHALL make `next` exit non-zero. Under `light`, `next_action` SHALL return `propose` and `revise` at tier `standard`, the critic SHALL resolve one tier above the logged proposer, a green gate with `last_verify_result: warnings:<m>` SHALL return `tasks-open` instead of `sweep`, and `split` at `applying` SHALL be tier `none` with a reason naming `units single`, so the change runs as exactly one unit. Every other output SHALL match `full`, including `gate0`. Under `light`, the single unit's worker SHALL be the proposer's resumed worker when the host supports resuming an agent, and otherwise a fresh `standard` worker; `next` output is the same either way. Triage sets `light` on the bugfix change it opens, and the human sets it through Gate 0's light option. The orchestrator never picks it for any other change.

#### Scenario: Light drafts at standard
- **WHEN** a change with `lifecycle: light` is at `proposed` with no draft
- **THEN** `next` returns `action: propose` and `tier: standard`

#### Scenario: Light critic one tier above
- **WHEN** a light change has a `proposed` session entry at `tier standard`
- **THEN** `next` returns `action: critique` and `tier: deep`

#### Scenario: Light skips the sweep
- **WHEN** a light change is `checking` with `last_gate_result: green`, `last_verify_result: warnings:2`
- **THEN** `next` returns `action: tasks-open`, while the same state under `full` returns `action: sweep`

#### Scenario: Light keeps Gate 0
- **WHEN** a light change's critique is `clean`
- **THEN** `next` returns `action: gate0`

#### Scenario: Light runs one unit
- **WHEN** a light change is at `applying` with `units` empty
- **THEN** `next` returns `action: split`, `tier: none`, and a reason containing `units single`

#### Scenario: Doc states light Apply and who sets light
- **WHEN** a reader checks AUTONOMOUS-ORCHESTRATION.md Phases step 4, "Bugs found mid-run", and Gate 0
- **THEN** step 4 says light Apply runs one unit whose worker is the resumed proposer when the host can, else a fresh `standard` worker; triage and Gate 0's light option are named as the only two ways `light` gets set; and the orchestrator never picks `light` itself

### Requirement: Checker input contract
`model critic` and `model verify` SHALL print the bare model id on the first line, followed by static `input:` lines (they read no state file; the seam list is named as the `seams` field, not resolved) listing the checker's inputs (critic: request, draft, seam list, prior report; Verify: proposal, seam list, branch diff, prior report) and the rule that other files are read only to confirm a seam or a dependency claim, never to explore the codebase. `model critic --unit <u>` SHALL print the same model id as `model critic`, followed by the unit-critic `input:` lines: proposal and delta spec, the unit's files and task ids, the unit diff from its `base`, the checks diff to its `checks_commit`, its screenshots as listed by `units ready-for-review` and opened with an image-capable read, and the prior unit critique, plus the same rule line.

#### Scenario: Contract emitted
- **WHEN** `model verify` runs for a change with history
- **THEN** line 1 is exactly the checker model id and later lines include `input:` and `seam`

#### Scenario: Contract for an initiative critic
- **WHEN** `model critic --name <initiative>` runs for an initiative that has a `proposed` session entry and no change state file
- **THEN** it prints the model id followed by the `input:` lines

#### Scenario: Unit-critic contract
- **WHEN** `model critic --name <change> --unit ui` runs
- **THEN** line 1 equals line 1 of `model critic --name <change>`, and later lines include `input:`, `screenshot`, and `checks_commit`
