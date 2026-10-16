# install.sh is the only distribution path; CHANGELOG.md replaces Atlas release metadata

The repository was published as an Atlas catalog (`atlas-catalog.json`, `releases.json`, `atlas bump`, a CI check for one new release per change) alongside a standalone installer. Atlas distribution is removed outright: `tools/install.sh` is the one path into every host tool, versions are recorded as headings in a root `CHANGELOG.md` with the same CI rule (installed files changed ⇒ exactly one new release), and the Atlas-shaped artefacts go with it — the OpenCode `-opencode` agent-name suffix, which only mirrored how Atlas filed agents, and the legacy unsuffixed `agents/openspec-<role>/` set Atlas installed for Claude Code. No deprecation period: the Atlas path had shipped for one day.

## Considered Options

- Keep the catalog frozen as a deprecation pointer — rejected: a catalog listing 100 agents that no longer match the repository is worse than none.
- Drop release metadata entirely and rely on git tags — rejected: the one-release-per-change rule was the Atlas-era convention worth keeping, and it needs a file CI can check.
- Keep `releases.json` hand-edited — rejected: the `1.2.1` entry records moving away from hand edits.

## Consequences

- Removing a distribution path and renaming OpenCode agents is breaking; this change ships as `3.0.0`, with `v2.1.0` tagged on the last Atlas-era commit.
- `openspec/config.yaml`'s context block and the `atlas-catalog-integration` spec describe a mechanism that no longer exists and are rewritten or removed with this change.
