# grill-mode Specification

## Purpose
TBD - created by archiving change add-grill-mode. Update Purpose after archive.

## Requirements

### Requirement: Grill mode replaces discovery mode
SKILL.md SHALL contain exactly one `## Grill mode` section, and SKILL.md, README.md and `atlas-catalog.json` SHALL contain no `/sdd:explore`. The SKILL.md frontmatter `description` and the `atlas-catalog.json` skill `description` SHALL be identical and SHALL contain `grill mode`. The **Autonomous only** section SHALL name grill mode as the only invocation that is not a full run, preceding a change rather than being a phase of one, with Gate 0 the only pause inside a change. README's Usage SHALL show a grill-mode invocation `/openspec-orchestrator grill`. SKILL.md SHALL NOT contain `grill-with-docs`.

#### Scenario: No discovery-mode references remain
- **WHEN** `tests/run.sh` runs `grep -c '/sdd:explore'` on SKILL.md, README.md and `atlas-catalog.json`
- **THEN** each count is 0, and `grep -c '^## Grill mode$' SKILL.md` is 1

#### Scenario: Descriptions identical and name grill mode
- **WHEN** `tests/run.sh` extracts the SKILL.md frontmatter `description:` value and the `"description"` string of `atlas-catalog.json`
- **THEN** the two strings are equal and contain `grill mode`, and the SKILL.md `description:` line contains exactly one `: ` (the key's) and no ` #`, so the frontmatter stays a plain YAML scalar

#### Scenario: Autonomous only names grill mode
- **WHEN** the lines from `## Autonomous only` to the next `## ` heading of SKILL.md are read
- **THEN** they contain `grill mode` and no `/sdd:explore`

#### Scenario: README example
- **WHEN** README.md is read
- **THEN** it contains `/openspec-orchestrator grill`

#### Scenario: No combined skill
- **WHEN** `grep -c 'grill-with-docs' SKILL.md` runs
- **THEN** the count is 0

### Requirement: Grill mode procedure
The Grill mode section SHALL state, in this order: Step 0 checks 1–3 and Steps 1–2 resolve the root first; in external mode, `git status --porcelain` of the project is captured; the first round reads the relevant code, specs and active changes and presents two or three approaches with trade-offs and a recommendation, and a session that stops there with no term or decision resolved writes nothing; the orchestrator then invokes the `grilling` and `domain-modeling` skills itself, telling domain-modeling that the Project glossary is `<root>/openspec/CONTEXT.md` and ADRs go in `<root>/openspec/adr/`, the same relative path in both modes, with the target project's own root `CONTEXT.md` and `docs/adr/` read as vocabulary only, never written; in external mode the captured status MUST be unchanged after the session, otherwise the orchestrator stops and reports the difference; writes stay uncommitted; the session ends with a sharpened request summary and an offer to start the change with it. When `domain-modeling` is unavailable the interview SHALL run without glossary or ADR writes, and when `grilling` is unavailable the orchestrator SHALL run its own inline interview rounds, with no message in either case.

#### Scenario: Section names every step
- **WHEN** `tests/run.sh` reads the lines from `## Grill mode` to the next `## ` heading of SKILL.md
- **THEN** they contain each of `Step 0`, `two or three approaches`, `grilling`, `domain-modeling`, `<root>/openspec/CONTEXT.md`, `<root>/openspec/adr/`, `docs/adr/`, `git status --porcelain`, `no message`, `uncommitted`, `sharpened request`, and `Gate 0`

### Requirement: Only grill mode writes the Project glossary and ADRs
SKILL.md **Guardrails** SHALL state that only grill mode writes the Project glossary and ADRs, and that Propose and Archive may cite an ADR or name the one a proposal supersedes but never edit either.

#### Scenario: Guardrail present
- **WHEN** the lines from `## Guardrails` to the end of SKILL.md are read
- **THEN** they contain `Project glossary` and `grill mode`

### Requirement: Grill-mode vocabulary documented
CONTEXT.md SHALL define **Project glossary** and **Grill mode**, and its **Checker input contract** entry SHALL list the Project glossary and ADRs among the critic's inputs. The `context:` block of the store's `openspec/config.yaml` SHALL name `openspec/CONTEXT.md` as the grill-mode-written Project glossary. README's repository-layout row for `CONTEXT.md` SHALL distinguish it from a target project's `<root>/openspec/CONTEXT.md`.

#### Scenario: Entries present
- **WHEN** `tests/run.sh` greps CONTEXT.md for `**Project glossary**` and `**Grill mode**` and extracts the **Checker input contract** entry
- **THEN** both entries are found and the extracted entry contains `Project glossary`

#### Scenario: Config context and README consistent
- **WHEN** `tests/run.sh` locates `openspec/CONTEXT.md` in `openspec/config.yaml` and reads README's layout row containing `` [`CONTEXT.md`] ``
- **THEN** the config hit lies inside the `context:` block and the README row contains `openspec/CONTEXT.md`
