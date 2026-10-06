## MODIFIED Requirements

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
