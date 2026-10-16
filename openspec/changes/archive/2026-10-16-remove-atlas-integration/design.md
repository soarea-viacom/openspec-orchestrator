# Design: remove-atlas-integration

## Context

See proposal.md (Why) and ADR 0001. The current Atlas surface:

- `atlas-catalog.json`: 5 legacy and 100 per-tool agent keys plus one skill entry. The last block of `tools/build-agents.sh` rewrites it.
- `tools/build-agents.sh`: has two loops. The first writes the legacy `agents/openspec-<role>/AGENT.md`. The second writes `agents/<tool>/openspec-<role>-<tier>/AGENT.md` and collects catalog rows.
- `skills/openspec-orchestrator/releases.json`: 21 entries, `1.0.0` to `2.1.0`. `tools/check-release-bump.sh` diffs it against the merge-base, and the `Release bump` step in `.github/workflows/ci.yml` calls the script on PRs.
- `role_agent` in `lib.sh` appends `-opencode` on OpenCode. `tools/install.sh` matches this with `ENTRY=NAME-opencode.md`.
- Tests that encode the old world: `tests/t-00-static.sh` (legacy agent loop, catalog counts, drift hash over `agents atlas-catalog.json`, the OpenCode suffix link, `/sdd:explore` grep over the catalog, SKILL.md/catalog description identity) and `tests/t-20-models.sh` (the `-opencode` agent line).
- `.README.md.swp` is a tracked vim swap file holding an older README with the Atlas section in it.

This repository's `gate_quick` is `bash -n` only. Unit checks are `tests/t-*.sh` files, so a worker runs its own with `tests/run.sh <stem>` (for example `tests/run.sh 85-release`), and `gate_full` (`./tests/run.sh`) runs them all.

## Goals / Non-Goals

**Goals:** carry out ADR 0001 with no engine runtime change except the OpenCode agent name. Keep every invariant the old tests checked on the agents that remain. Turn each requirement in `specs/installed-files/spec.md` into a test.

**Non-Goals:**
- Editing archived change records, `docs/research/`, `openspec/CONTEXT.md`, `openspec/adr/` or `.claude/settings.local.json`.
- Writing a deprecation notice for Atlas consumers.
- Making the Installer clean up old `-opencode.md` links.
- Making the release check reject a new Release on a change that touches no installed files. Today's strictness is kept.
- Editing the living specs under `openspec/specs/` by hand. Archive applies this change's deltas to them and removes `openspec/specs/atlas-catalog-integration/` (see Migration Plan).
- Editing `tests/t-30-next.sh`. Its overlay fixture text "Verify the bump in releases.json…" is an arbitrary string passed through to an overlay, not an Atlas reference.

## Decisions

### Units and seams

There are three units, cut along three seams. Each unit has at most 3 tasks. `release-metadata` and `docs` have at most 7 file entries; `agents-and-installer` has 12, recorded in `unit_size_ok`.

| unit | files | deps |
|---|---|---|
| `release-metadata` | `CHANGELOG.md`, `skills/openspec-orchestrator/releases.json`, `tools/check-release-bump.sh`, `.github/workflows/ci.yml`, `tests/t-85-release.sh` | none |
| `agents-and-installer` | `tools/build-agents.sh`, `tools/install.sh`, `agents/`, `atlas-catalog.json`, `skills/openspec-orchestrator/scripts/lib.sh`, `tests/t-00-static.sh`, `tests/t-20-models.sh`, `agents/openspec-critic/AGENT.md`, `agents/openspec-proposer/AGENT.md`, `agents/openspec-unit-critic/AGENT.md`, `agents/openspec-verifier/AGENT.md`, `agents/openspec-worker/AGENT.md` | none |
| `docs` | `README.md`, `.README.md.swp`, `skills/openspec-orchestrator/SKILL.md`, `skills/openspec-orchestrator/AUTONOMOUS-ORCHESTRATION.md`, `skills/openspec-orchestrator/CONTEXT.md`, `openspec/config.yaml`, `tests/t-00-static.sh` | `release-metadata`, `agents-and-installer` |

`docs` depends on both other units for two reasons. First, its acceptance check is the repo-wide Atlas grep, which can only pass after the catalog, `releases.json` and the code comments are gone. Second, it shares `tests/t-00-static.sh` with `agents-and-installer`, and the dependency puts those two edits in order. `agents-and-installer` owns the catalog-related lines of `t-00-static.sh` because deleting the catalog breaks those lines at once (the `/sdd:explore` loop and the description comparison read the file).

`agents/` holds about 100 generated files that `tools/build-agents.sh` regenerates. A worker never edits a file under `agents/` by hand. It changes the generator and reruns it. The engine's unit scope check matches changed paths exactly, so `agents/` does not cover the five deleted `agents/openspec-<role>/AGENT.md` files; they are listed as their own entries, which puts the unit at 12 entries and is why `unit_size_ok agents-and-installer` is recorded.

### Generator owns all of `agents/`

`tools/build-agents.sh` loses the legacy loop, the `catalog_rows` accumulation, the Python catalog writer and the Atlas wording in its comments. Its `rm -rf` of the five tool directories becomes `rm -rf agents`, so stale directories such as the legacy five cannot survive a regeneration.
- Alternative considered: deleting `agents/openspec-<role>/` by hand once. Rejected because a stray directory could come back unnoticed. Either way, the test "exactly five directories under `agents/`" catches it.

The header comment then describes the one output, `agents/<tool>/openspec-<role>-<tier>/AGENT.md`. The per-tool comment keeps only the remaining non-obvious rationale: Copilot carries the fallback as a priority list, and Codex's model is written as TOML by `tools/install.sh`.

### Role agent name

In `role_agent`, delete the `suffix` line and echo `openspec-$2-$tier`. Its comment keeps the reason a checker on a fallback model names another tier's agent and drops the two OpenCode/Atlas sentences.

In `tools/install.sh`, both `opencode` cases become `ENTRY=NAME.md`. The `ENTRY` comment shrinks to its first sentence, and the header loses "(no Atlas)". Nothing else in `lib.sh` or `run-change` changes, which the guardrail diff check enforces.

### CHANGELOG.md format

```
# Changelog

## 3.0.0

<3.0.0 note>

## 2.1.0

<releases.json["2.1.0"] verbatim>
...
## 1.0.0

<releases.json["1.0.0"] verbatim>
```

Each paragraph is one line, copied character for character from `releases.json`. That includes the leading `2.0.0: ` of the 2.0.0 entry and the missing final period of 1.10.0. The verbatim copy is what lets the release check compare old and new text.

The 3.0.0 note should run along these lines (illustrative wording): the Atlas catalog is removed and `tools/install.sh` is the only install path; release notes move from `releases.json` to `CHANGELOG.md`; OpenCode agents are installed as `openspec-<role>-<tier>.md`, so re-run `tools/install.sh --tool opencode` and delete the old `openspec-*-opencode.md` links; and the unsuffixed `agents/openspec-<role>/` set is gone.

### check-release-bump.sh

The usage `check-release-bump.sh <base-ref>` and the installed-file trigger (`git diff --name-only <mb> HEAD -- skills/openspec-orchestrator agents`) stay the same, so `.github/workflows/ci.yml` is unchanged. The worker confirms the step still reads `tools/check-release-bump.sh "origin/${{ github.base_ref }}"`.

The parsing stays in python3's standard library, with both sides read through `git show`:
- New side: `HEAD:CHANGELOG.md`, so the result describes the same commit the diff does.
- Old side: `<mb>:CHANGELOG.md`, or `<mb>:skills/openspec-orchestrator/releases.json` when the base has no `CHANGELOG.md`.

Each side is parsed into a `{version: paragraph}` map. The paragraph is the section text with blank lines stripped. The rules are today's:
- exactly one added version;
- the added version is above the old maximum, compared as integer tuples;
- every old version is present with an identical paragraph.

Error messages name `CHANGELOG.md`, the count found or the offending version, and contain no `atlas bump` hint.
- Alternative considered: no `releases.json` fallback. Rejected because this PR's own CI would see 22 "new" Releases and fail. With the fallback, the same rule also proves the migration is verbatim. After merge it is reachable only from branches based before this change, and a later change may remove it.

### t-85-release.sh (new)

`tests/t-85-release.sh` is self-contained like the other `t-*.sh` files and uses `tests/lib.sh`. The script resolves the repository from its own location (`cd "$(dirname …)/.."`), so each case builds a temporary git repo, copies `tools/check-release-bump.sh` into that repo's `tools/`, commits a base on `main`, branches, commits the case and runs `tools/check-release-bump.sh main` inside the repo. It covers the seven script scenarios of the requirement "A change to installed files carries exactly one new Release". It also covers the static checks on the real `CHANGELOG.md`: at least 22 headings, strictly descending, `## 3.0.0` present, line 1 `# Changelog`, one paragraph per section, and the OpenCode migration text in 3.0.0. It checks that `releases.json` is absent and unreferenced, and that `ci.yml` has the step.

### Atlas-free check

The check lives in `t-00-static.sh` and is added by the `docs` unit:

```
git grep --untracked -n -i '[a]tlas' -- . ':!.orchestration' ':!.claude' ':!openspec/changes' \
  ':!openspec/specs' ':!openspec/CONTEXT.md' ':!openspec/adr' ':!docs/research' ':!CHANGELOG.md'
```

It must print nothing. `--untracked` covers files a worker has not committed yet, and ignored files (`.orchestration/workspaces/`) stay out. The pattern `[a]tlas` does not match its own source line.

Each exclusion beyond the request's list has a reason:
- `.claude/`: holds the untracked `settings.local.json`, which is out of scope.
- `openspec/changes/`: covers the archive (history) and this change's own artifacts, which must name what they remove.
- `openspec/specs/`: the living specs change only when archive applies these deltas, and the full gate runs before archive.
- `openspec/CONTEXT.md` and `openspec/adr/`: owned by grill mode and must not be edited.
- `CHANGELOG.md`: the verbatim history (1.0.0, 1.2.1, 1.9.0, 2.1.0) and the 3.0.0 note.

### t-00-static.sh and t-20-models.sh edits

`agents-and-installer` makes these edits:
- The `AGENT_EFFORT` loop moves to `agents/claude-code/openspec-$role-$tier/AGENT.md` for every tier. It checks the effort, the body verbatim, no `Agent` tool, and no `Edit` for checkers.
- Both catalog-count checks are removed.
- The drift hash covers `find agents -type f` only.
- New check: exactly the five tool directories exist under `agents/`.
- New check: each `AGENT.md` `name:` equals its directory name.
- The OpenCode install check becomes `$IH/.config/opencode/agents/openspec-critic-max.md`, with no `*-opencode.md` file present.
- The `/sdd:explore` loop runs over SKILL.md and README.md only.
- The description-identity check is removed. The "description names grill mode" check stays.
- In `t-20-models.sh`, the OpenCode line asserts `agent: openspec-proposer-standard`, and a `check_not` asserts that no `-opencode` line appears.

`docs` adds to `t-00-static.sh`:
- the Atlas-free grep;
- the docs checks of the requirement "Docs describe only the Installer".

### Docs edits

**README.md**
- Line 9 becomes "Runs on Claude Code, Cursor, VS Code/Copilot, Codex and OpenCode."
- The `releases.json` table row is deleted.
- "Without Atlas, from a checkout:" becomes "From a checkout:".
- On line 134, the clause after the semicolon (the `-opencode` suffix sentence) is dropped. The Codex TOML clause before it stays: it is the only place that fact is documented once the Atlas section is gone.
- The whole "Install via Atlas" section is deleted. The paragraph "Each agent pins its tier's default model … at the session's effort." moves to the end of "Install the skill", without the "remain for one release" sentence.
- The Tests line names one new `CHANGELOG.md` Release.

**SKILL.md**, Step 0:
- "runs on Claude Code, Cursor, VS Code/Copilot, Codex, OpenCode";
- "installed by `tools/install.sh --tool <tool>`", with the Atlas parenthesis removed.

**AUTONOMOUS-ORCHESTRATION.md**, Role agents section:
- "installed by `tools/install.sh --tool <tool>`";
- the catalogued-name clause, the `-opencode` parenthesis and the legacy-five sentence are dropped.

**CONTEXT.md** (skill), Role agent entry: drop "catalogued as … suffix", and state that the name is the same on every host.

**openspec/config.yaml**, `context:`:
- The installed files are `skills/openspec-orchestrator/` (SKILL.md, AUTONOMOUS-ORCHESTRATION.md, CONTEXT.md, models.tsv, scripts/) and `agents/`. The Installer copies the skill directory whole, so nothing the engine needs at run time may live outside it.
- Every change to installed files adds exactly one Release (`## <version>`, newest first) to the root `CHANGELOG.md`, which CI enforces with `tools/check-release-bump.sh`.

`.README.md.swp` is deleted with `git rm`.

## Risks / Trade-offs

- [Placeholders such as `<slug>` and `<root>` in the verbatim entries render as raw HTML on GitHub and disappear from the rendered view] → Accepted. Verbatim text is the human's decision and what the migration check compares. The raw file stays exact.
- [Existing OpenCode installs keep dangling `openspec-*-opencode.md` links] → The 3.0.0 note says to delete them, and the Installer stays free of suffix logic.
- [The `releases.json` fallback in the release check outlives its one use] → It runs only when the base predates `CHANGELOG.md`, is covered by `t-85`, and is safe to remove later.
- [Excluding `openspec/specs/` from the Atlas grep could hide a stale living spec, such as `openspec/specs/atlas-catalog-integration/`] → Archive applies the REMOVED and MODIFIED deltas, `openspec validate --strict` checks them first, and the Migration Plan requires that directory to be gone after archive.

## Migration Plan

1. Merge the change.
2. Post-merge manual task: tag the `main` tip immediately before this PR merges (today `65043a9`) as `v2.1.0` and push the tag.
3. Archive the change. Afterwards `openspec/specs/atlas-catalog-integration/` does not exist; if archive leaves an empty spec, the directory is deleted in the archive commit.

Rollback: revert the merge commit, which restores the catalog, `releases.json` and the previous release check together.
