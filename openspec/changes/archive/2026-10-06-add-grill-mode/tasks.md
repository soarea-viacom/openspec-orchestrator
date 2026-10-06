# Tasks

## 1. Checks (tests/run.sh)

- [x] 1.1 Critic contract checks beside the existing `model critic` contract cases (design D8): `model critic --store teststore --name feat-critic` has a line starting `input: the Project glossary` containing `$STORE/openspec/CONTEXT.md` and a line starting `input: the ADRs` containing `$STORE/openspec/adr/` and `supersedes`, both with `grep -n` numbers greater than the `input: seam list` line's and less than the `input: the prior critic report, if any` line's; `model verify --store teststore --name feat-verify` and `model critic --store storeu3 --name feat-owner --unit a` contain neither `openspec/CONTEXT.md` nor `openspec/adr/`. Verify: `./tests/run.sh` lists these cases (red until 2.1).
- [x] 1.2 Extend `ROLE_INVARIANTS` with proposer `openspec/CONTEXT.md`, `openspec/adr/`, `never edit` and critic `openspec/CONTEXT.md`, `openspec/adr/`, `names the ADR it supersedes`, `non-canonical term`; leave the anchor and 20-line checks unedited. Verify: the new `role prompt … quotes:` cases appear in `./tests/run.sh` output (red until 2.2).
- [x] 1.3 Doc checks in the trailing `docs:` block (design D8): `/sdd:explore` count 0 in SKILL.md, README.md, `atlas-catalog.json`; one `^## Grill mode$`; the Grill mode section (heading to next `^## `) contains each literal in the grill-mode spec's "Section names every step" scenario; no `grill-with-docs` in SKILL.md; the Autonomous only section contains `grill mode`; the Guardrails section contains `Project glossary` and `grill mode`; SKILL.md frontmatter description equals the catalog description and contains `grill mode`, and the SKILL.md `description:` line contains exactly one `: ` and no ` #`. Verify: cases listed in `./tests/run.sh` output (red until 3.1–3.2).
- [x] 1.4 Doc checks: CONTEXT.md `**Project glossary**`, `**Grill mode**`, and the extracted **Checker input contract** entry contains `Project glossary`; `openspec/CONTEXT.md` inside the `context:` block of `openspec/config.yaml` (same line-range logic as the existing `scripts/roles/<role>.md` check); README contains `/openspec-orchestrator grill` and its `` [`CONTEXT.md`] `` layout row contains `openspec/CONTEXT.md`; AUTONOMOUS-ORCHESTRATION.md's `**Critique**`…`The critic writes a **critique report**` range contains `openspec/CONTEXT.md` and `openspec/adr/`. Verify: cases listed in `./tests/run.sh` output (red until 3.3–3.5).

## 2. Implementation

- [x] 2.1 `skills/openspec-orchestrator/scripts/lib.sh` `checker_inputs`, `critic)` branch only: print the two D5 lines after the seam line, paths from `store_path "$slug"`. Verify: `bash -n skills/openspec-orchestrator/scripts/lib.sh`; 1.1 cases green; existing `model critic` / `model verify` / `--unit` contract cases still green.
- [x] 2.2 `skills/openspec-orchestrator/scripts/roles/proposer.md` and `critic.md`: add the D5 lines verbatim (proposer before its `validate --strict` line, critic after its five-standards line). Verify: 1.2 cases green; every `role prompt proposer|critic:` anchor and 20-line case still green.

## 3. Docs

- [x] 3.1 SKILL.md: `## Grill mode` section per D1–D6 between **Autonomous only** and **Optional convenience**; **Autonomous only** last sentences per D7; Guardrails bullet per D7; frontmatter `description` per D7, unquoted, with no `: ` or ` #` in the value. Verify: 1.3 SKILL.md cases green.
- [x] 3.2 `atlas-catalog.json` `description`: the same string as SKILL.md's, edited in place (no re-serialization). Verify: description-equality case green; `git diff atlas-catalog.json` touches one line.
- [x] 3.3 CONTEXT.md: add **Project glossary** and **Grill mode**; amend **Checker input contract** critic list (D7). Verify: 1.4 CONTEXT.md cases green.
- [x] 3.4 AUTONOMOUS-ORCHESTRATION.md Critique paragraph input-contract sentence (D7); `openspec/config.yaml` `context:` sentence (D7). Verify: 1.4 AUTONOMOUS and config cases green; `git diff` of AUTONOMOUS-ORCHESTRATION.md touches only the Critique paragraph.
- [x] 3.5 README.md: Usage grill example and lead-in; layout-table `CONTEXT.md` row (D7). Verify: 1.4 README cases green; `./tests/run.sh` ends with `all tests passed` and prints `ok   no engine function without a caller`.

## 4. Release

- [x] 4.1 `atlas bump skill openspec-orchestrator --minor -m "Add grill mode, replacing /sdd:explore as the only pre-change mode: explore's analysis first, then grilling and domain-modeling write the Project glossary (<root>/openspec/CONTEXT.md) and ADRs (<root>/openspec/adr/), with an external-mode git status guard; the proposer and critic read both, and the critic blocks on an unsuperseded ADR contradiction"` — never hand-edit releases.json. Verify: `git diff main -- skills/openspec-orchestrator/releases.json` adds exactly one key, `1.10.0`.
