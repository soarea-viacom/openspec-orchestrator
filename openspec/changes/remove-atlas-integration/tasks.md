# Tasks

## 1. Release metadata (unit `release-metadata`)

- [x] 1.1 Create root `CHANGELOG.md`: `# Changelog`, then `## 3.0.0` with the 3.0.0 note (design.md, CHANGELOG.md format), then the 21 `releases.json` entries newest first, each paragraph copied verbatim on one line, no dates; `git rm skills/openspec-orchestrator/releases.json`. Verify: the CHANGELOG checks in `tests/run.sh 85-release` pass (at least 22 headings, strictly descending, `## 3.0.0` present, one paragraph each, 3.0.0 names `tools/install.sh --tool opencode` and `-opencode.md`), and `grep -rl releases.json skills/openspec-orchestrator` finds nothing.
- [x] 1.2 Retarget `tools/check-release-bump.sh` to `CHANGELOG.md` headings (HEAD vs merge-base via `git show`, base `releases.json` fallback, today's three rules, no `atlas` in messages or comments); leave `.github/workflows/ci.yml`'s `Release bump` step as is. Verify: `tools/check-release-bump.sh main` on this branch exits 0 and prints `3.0.0`; `grep -F 'tools/check-release-bump.sh "origin/${{ github.base_ref }}"' .github/workflows/ci.yml` matches.
- [x] 1.3 Add `tests/t-85-release.sh`: temp-git-repo cases for one new Release (pass), none (fail), two (fail), not above (fail), edited earlier Release (fail), non-installed change only (pass), base with `releases.json` only (pass verbatim, fail altered); plus the static CHANGELOG, `releases.json`-absent and `ci.yml` checks. Verify: `tests/run.sh 85-release` green.

## 2. Agents and Installer (unit `agents-and-installer`)

- [x] 2.1 In `tools/build-agents.sh` remove the legacy `agents/openspec-<role>/` loop, `catalog_rows` and the catalog-writing Python block, clear `agents/` whole before generating, and rewrite the header and per-tool comments without Atlas; `git rm atlas-catalog.json` and the five `agents/openspec-<role>/` directories; rerun `tools/build-agents.sh`. Verify: `ls agents` prints exactly `claude-code codex copilot cursor opencode`, a second `tools/build-agents.sh` run leaves `git status --porcelain agents` empty, and `test ! -e atlas-catalog.json`.
- [x] 2.2 Drop the `-opencode` suffix: `role_agent` in `skills/openspec-orchestrator/scripts/lib.sh` echoes `openspec-<role>-<tier>` (comment loses the OpenCode/Atlas sentences); both `opencode` cases in `tools/install.sh` use `ENTRY=NAME.md`, its `ENTRY` and header comments lose the suffix and Atlas wording; `tests/t-20-models.sh` asserts `agent: openspec-proposer-standard` on OpenCode with no `-opencode` line. Verify: `tests/run.sh 20-models` green.
- [x] 2.3 Update `tests/t-00-static.sh` agent and catalog checks per design.md (claude-code per-tier effort/tools/body loop, no catalog counts, drift hash over `agents` only, five-directory and `name:`-equals-directory checks, OpenCode `openspec-critic-max.md` link and no `*-opencode.md`, `/sdd:explore` loop without the catalog, description-identity check removed). Verify: `tests/run.sh 00-static` green.

## 3. Docs (unit `docs`, after `release-metadata` and `agents-and-installer`)

- [x] 3.1 Edit `README.md` per design.md (line 9, `releases.json` row, "From a checkout:", the clause after the semicolon on line 134 (`-opencode`; the Codex TOML clause stays), "Install via Atlas" section removed with its agent paragraph moved under "Install the skill" minus the legacy sentence, Tests line names `CHANGELOG.md`); `git rm .README.md.swp`. Verify: `grep -ci atlas README.md` is 0, `grep -F 'model_reasoning_effort' README.md`, `grep -F 'Agent definitions load when a session starts' README.md` and `grep 'CHANGELOG.md' README.md | grep -F tools/check-release-bump.sh` all match.
- [x] 3.2 Edit `skills/openspec-orchestrator/SKILL.md` Step 0, `AUTONOMOUS-ORCHESTRATION.md` Role agents section, the skill `CONTEXT.md` Role agent entry, and the `context:` block of `openspec/config.yaml` per design.md. Verify: `grep -ci atlas` on all four is 0; `grep -cF -- '-opencode'` and `grep -cF 'agents/openspec-<role>/'` on the three skill docs and README are 0; Step 0 contains `tools/install.sh --tool <tool>`; the config context contains `CHANGELOG.md`, `agents/` and `exactly one`.
- [x] 3.3 Add to `tests/t-00-static.sh` the Atlas-free `git grep --untracked -i '[a]tlas'` check with the design.md exclusions and the docs checks of "Docs describe only the Installer". Verify: `tests/run.sh` green.

## 4. Change verification (whole change, after all units merge)

- [ ] 4.1 `openspec validate remove-atlas-integration --strict --store github-com-soarea-viacom-openspec-orchestrator` passes.
- [ ] 4.2 Guardrails hold against `main`: `git diff main -- skills/openspec-orchestrator/scripts/run-change` is empty; `git diff -U0 main -- skills/openspec-orchestrator/scripts/lib.sh` touches only `role_agent` and its comment; `git diff --name-only --diff-filter=MDR main -- openspec/changes/archive openspec/CONTEXT.md openspec/adr docs/research .claude` is empty; `git diff --name-only main -- tests` lists only `tests/t-00-static.sh`, `tests/t-20-models.sh`, `tests/t-85-release.sh`; no new dependency manifest or tool appears (`git diff --name-only --diff-filter=A main` lists only `CHANGELOG.md`, `tests/t-85-release.sh`, `openspec/CONTEXT.md`, `openspec/adr/*` and `openspec/changes/remove-atlas-integration/**`).
- [ ] 4.3 `./tests/run.sh` green and `tools/check-release-bump.sh main` exits 0 printing `3.0.0`.

## 5. Post-merge (manual)

- [ ] 5.1 After merge, tag the `main` tip immediately before this PR merges (today `65043a9`) as `v2.1.0` and push the tag: `git tag v2.1.0 <sha> && git push origin v2.1.0`; confirm with `git rev-parse v2.1.0^{commit}`.
- [ ] 5.2 After archive, `test ! -e openspec/specs/atlas-catalog-integration` passes; if archive leaves an empty spec, delete the directory in the archive commit.
