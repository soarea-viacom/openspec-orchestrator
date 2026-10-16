# Spec Delta

## REMOVED Requirements

### Requirement: Grill mode replaces discovery mode
**Reason**: two of its checks read `atlas-catalog.json`, which this change deletes. These are the `/sdd:explore` grep and the description-identity scenario. A MODIFIED block cannot drop a scenario.
**Migration**: replaced by "Grill mode replaces discovery mode in SKILL.md and README" below. It keeps every other clause and scenario, drops the catalog from the grep and drops the identity comparison.

## ADDED Requirements

### Requirement: Grill mode replaces discovery mode in SKILL.md and README
SKILL.md SHALL contain exactly one `## Grill mode` section, and SKILL.md and README.md SHALL contain no `/sdd:explore`. The SKILL.md frontmatter `description` SHALL contain `grill mode`. The **Autonomous only** section SHALL name grill mode as the only invocation that is not a full run, preceding a change rather than being a phase of one, with Gate 0 the only pause inside a change. README's Usage SHALL show a grill-mode invocation `/openspec-orchestrator grill`. SKILL.md SHALL NOT contain `grill-with-docs`.

#### Scenario: No discovery-mode references remain
- **WHEN** `tests/run.sh` runs `grep -c '/sdd:explore'` on SKILL.md and README.md
- **THEN** each count is 0, and `grep -c '^## Grill mode$' SKILL.md` is 1

#### Scenario: Description names grill mode
- **WHEN** `tests/run.sh` extracts the SKILL.md frontmatter `description:` value
- **THEN** it contains `grill mode`, and the SKILL.md `description:` line contains exactly one `: ` (the key's) and no ` #`, so the frontmatter stays a plain YAML scalar

#### Scenario: Autonomous only names grill mode
- **WHEN** the lines from `## Autonomous only` to the next `## ` heading of SKILL.md are read
- **THEN** they contain `grill mode` and no `/sdd:explore`

#### Scenario: README example
- **WHEN** README.md is read
- **THEN** it contains `/openspec-orchestrator grill`

#### Scenario: No combined skill
- **WHEN** `grep -c 'grill-with-docs' SKILL.md` runs
- **THEN** the count is 0
