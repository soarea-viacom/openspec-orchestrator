# Proposal: remove-atlas-integration

## Why

ADR 0001 makes the Installer (`tools/install.sh`) the only path from this repository into a host tool. The Atlas catalog, `releases.json`, the OpenCode `-opencode` agent-name suffix and the legacy `agents/openspec-<role>/` set exist only to serve the Atlas path. Each one now describes a mechanism that is gone, and the 100-agent catalog would drift from the repository.

## What Changes

- **BREAKING**: delete `atlas-catalog.json` and the catalog-writing block of `tools/build-agents.sh`. The Installer is the only install path.
- Release metadata moves from `skills/openspec-orchestrator/releases.json` to a root `CHANGELOG.md`. Each of the 21 existing entries becomes one `## <version>` heading, newest first, with its text copied verbatim as the paragraph and no dates. `releases.json` is deleted. `tools/check-release-bump.sh` is retargeted and keeps today's strictness: when installed files change against the base ref, exactly one new Release is required, it must sort above every earlier Release, and earlier Releases must not be edited or removed. The CI step in `.github/workflows/ci.yml` stays and runs the retargeted script.
- This change is Release `3.0.0`, and its CHANGELOG entry is part of the change.
- **BREAKING**: the Role agent name is `openspec-<role>-<tier>` on every host. `role_agent` in `skills/openspec-orchestrator/scripts/lib.sh` drops the OpenCode suffix, and the Installer files OpenCode agents as `<name>.md`.
- Delete the five legacy `agents/openspec-<role>/` directories and the generator loop that writes them. `agents/<tool>/openspec-<role>-<tier>/` becomes the only agent set.
- Remove every Atlas mention from `README.md`, `SKILL.md`, `AUTONOMOUS-ORCHESTRATION.md`, the skill's `CONTEXT.md`, the `context:` block of `openspec/config.yaml` and the Installer's header comment. This is a hard cut with no deprecation note. The tracked editor swap file `.README.md.swp` is a stale copy of the README with the Atlas section in it, so it is deleted.
- Specs: `atlas-catalog-integration` is removed. In `grill-mode`, the discovery-mode requirement is replaced by one that no longer names the catalog, and the description-identity scenario goes away with the catalog. The new capability `installed-files` records the Installer-only, Release and Role agent name rules.
- Tests: `tests/t-00-static.sh` and `tests/t-20-models.sh` move to the new world. A new `tests/t-85-release.sh` checks `CHANGELOG.md` and the behaviour of `check-release-bump.sh` against temporary git repositories. A repo-wide check fails on any Atlas mention outside the history paths.
- Manual, after merge: tag `v2.1.0` on the last pre-change commit.

## Capabilities

### New Capabilities
- `installed-files`: covers how Installed files reach host tools and how each change to them is recorded. The Installer is the only path, each change to installed files records one Release in `CHANGELOG.md`, and the Role agent name is the same on every host.

### Modified Capabilities
- `grill-mode`: the requirement "Grill mode replaces discovery mode" is replaced by "Grill mode replaces discovery mode in SKILL.md and README". The new requirement drops `atlas-catalog.json` from the `/sdd:explore` check and drops the description-identity scenario. The SKILL.md description must still name grill mode. The change is a REMOVED plus an ADDED because a MODIFIED block must restate every scenario of the living requirement, so the description-identity scenario cannot be dropped through it.

### Removed Capabilities
- `atlas-catalog-integration`: all three requirements (the catalog, release metadata for Atlas, the Atlas README instructions) are removed. After archive, `openspec/specs/atlas-catalog-integration/` must not exist; if archive leaves an empty spec, its directory is deleted in the archive commit.

## Pillars

- **scope=seams**: the change touches three independent seams. These are release metadata, agents and the Installer, and docs.
- **blast=public**: consumers lose the Atlas install path. OpenCode agent files are renamed, so an existing OpenCode install must re-run the Installer. This makes the change semver-major (`3.0.0`).
- **novelty=known**: the change deletes code and rewords docs. The one rewrite, `check-release-bump.sh`, keeps its current rules and only reads a different file.
- **deps=none**: no dependency is added or removed. The scripts keep using bash, git and the python3 standard library.

Shape: `full` lifecycle, deep tier, one change with three units (see design.md). No ADR is superseded. This change carries out ADR 0001.

## Guardrails

Guardrails: the engine's runtime behaviour does not change except the OpenCode agent name. That covers `next`, model picks, gates, units and state, and `run-change` stays byte-identical. Inside `lib.sh`, only `role_agent` and its comment change; no existing test file other than `t-00-static.sh` and `t-20-models.sh` is edited, and `tests/t-85-release.sh` is the only new one. No existing file under `openspec/changes/archive/` is modified or deleted, and neither are `openspec/CONTEXT.md`, `openspec/adr/` or `docs/research/`. `.claude/settings.local.json` is not touched. No new dependency is added. A grep check proves that no Atlas mention remains outside the excluded paths.

## Unit size

Every unit fits the cap (8 files, 3 tasks), so `unit_size_ok` is not needed. `agents/` counts as one entry because `tools/build-agents.sh` regenerates the whole directory.

## Impact

- Consumers on Atlas have no upgrade path. They install with `tools/install.sh --tool <tool>`.
- Existing OpenCode installs from the Installer keep stale `openspec-*-opencode.md` links until they are removed. The `3.0.0` entry in `CHANGELOG.md` tells those users to re-run the Installer and delete the old links.
- CI's release check reads `CHANGELOG.md`. This PR's own base still has only `releases.json`, so the script reads the base's Releases from that file when the base has no `CHANGELOG.md`. The same rule then proves the 21 migrated entries are verbatim.
