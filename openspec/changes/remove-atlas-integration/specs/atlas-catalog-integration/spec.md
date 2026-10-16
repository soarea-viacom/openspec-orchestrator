# Spec Delta

## REMOVED Requirements

### Requirement: Repo is a valid single-skill Atlas catalog
**Reason**: ADR 0001 makes the Installer (`tools/install.sh`) the only install path, so `atlas-catalog.json` is deleted.
**Migration**: Install with `tools/install.sh --tool <tool>` from a checkout. The `installed-files` requirement "The Installer is the only install path" replaces this one.

### Requirement: Skill has release metadata for versioning
**Reason**: `releases.json` existed for Atlas version commands, and those commands no longer apply.
**Migration**: Releases are `## <version>` headings in the root `CHANGELOG.md`. See the `installed-files` requirements "Releases are recorded in CHANGELOG.md" and "A change to installed files carries exactly one new Release".

### Requirement: Consumption is documented
**Reason**: the README's Atlas installation steps describe a path that no longer exists.
**Migration**: README documents only `tools/install.sh`. See the `installed-files` requirement "Docs describe only the Installer".
