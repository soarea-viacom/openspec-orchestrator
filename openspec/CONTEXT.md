# openspec-orchestrator (repository)

How this repository ships its skill and agents to the tools that run them. The engine's own domain glossary is `skills/openspec-orchestrator/CONTEXT.md`; this file covers only the repository's distribution vocabulary.

## Language

**Installed files**:
What a consumer receives: the skill directory `skills/openspec-orchestrator/` and the agent definitions under `agents/`. Everything else in the repository stays here.
_Avoid_: catalog contents, package, payload

**Installer**:
`tools/install.sh`, the only path from this repository into a tool's own skill and agent directories.
_Avoid_: Atlas, catalog install, distribution path

**Release**:
One version heading in the root `CHANGELOG.md` with the note consumers read. A change to installed files carries exactly one new release; a change to anything else carries none.
_Avoid_: bump, releases.json entry, version tag (a tag marks a release, it is not one)

**Role agent name**:
`openspec-<role>-<tier>`, the same on every host tool; the installed file carries exactly that name.
_Avoid_: catalog key, suffixed name, `-<tool>` suffix
