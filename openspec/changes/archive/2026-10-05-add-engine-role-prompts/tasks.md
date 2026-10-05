# Tasks

## 1. Checks (tests/run.sh)

- [ ] 1.1 Prompt-file checks: `scripts/roles/` holds exactly the five role files; each ≤20 lines with no line starting `#`; each contains its role's invariant strings (spec: Engine role prompt files). Verify: `./tests/run.sh` reports these cases (red until 2.2).
- [ ] 1.2 Anchor checks from the D3 table held as a literal in run.sh: per role, each assigned anchor counts 2 in the file, 1 on line 1, 1 on the last line (`seam` as a whole word excluding `<seam>` placeholders, `grep -oF` for the rest); each unassigned anchor counts 0. Verify: cases listed in `./tests/run.sh` output.
- [ ] 1.3 `roles prompt` checks: placed with the existing "roles get with no overlay" cases, before the `mkdir -p "$STORE/openspec/roles"` fixture, `--role verifier` → exit 0, output equals `scripts/roles/verifier.md`; after that fixture → engine last line precedes overlay first line, and `roles get --role critic` output unchanged; `--role reviewer` → non-zero with `unknown role`. Verify: cases in `./tests/run.sh` output.
- [ ] 1.4 `next` checks beside the existing overlay cases: critique (feat-next, critic overlay present) prints `prompt: $PWD/scripts/roles/critic.md`, asserted by `grep -n` line numbers — `prompt:` = `reason:` + 1 and `prompt:` < `overlay:`; fresh-change propose (no proposer overlay is ever created in run.sh) prints `prompt: $PWD/scripts/roles/proposer.md` and no `overlay:`; `check` (the existing case before the verifier fixture) prints `also_prompt: $PWD/scripts/roles/verifier.md` with its `grep -n` number = `also_model:` + 1; `tasks-open` prints no `prompt:`. Existing overlay assertions stay unedited. Verify: cases in `./tests/run.sh` output.

## 2. Implementation

- [ ] 2.1 `scripts/lib.sh`: `role_prompt <role>` (D1); rename `emit_overlay` → `emit_role_lines`, printing `prompt:` before `overlay:` (D2); `check` branch prints `also_prompt:` before the `also_overlay:` block; add `prompt`/`also_prompt` to the `next_action` output comment. Verify: `bash -n scripts/lib.sh`; 1.4 cases green.
- [ ] 2.2 `scripts/roles/{proposer,critic,worker,unit-critic,verifier}.md` per D3/D4; `verifier.md` is the D4 worked example verbatim. Verify: 1.1 and 1.2 cases green.
- [ ] 2.3 `scripts/run-change`: `cmd_roles_prompt` (D2), `"roles prompt"` dispatch entry, usage line `roles prompt   --store <slug> --role proposer|critic|worker|unit-critic|verifier`. Verify: 1.3 cases green; `./tests/run.sh` prints `ok   no engine function without a caller` and ends with zero failures.

## 3. Docs

- [ ] 3.1 AUTONOMOUS-ORCHESTRATION.md: Hard rule style-split bullet; Role overlays (engine prompt files, `prompt:`/`also_prompt:`, `roles prompt` order); Driving the loop (two new lines); Unit workers (worker prompt in the dispatch) — no existing invariant sentence reworded (D5). Verify: `grep -n 'scripts/roles' AUTONOMOUS-ORCHESTRATION.md` hits Role overlays and Hard rule; `git diff` shows no edited invariant sentence.
- [ ] 3.2 SKILL.md Guardrails last bullet: the role's engine prompt (`scripts/roles/<role>.md`, `next` prints `prompt:`) precedes the appended overlay. Verify: `grep -n 'prompt:' SKILL.md`.
- [ ] 3.3 CONTEXT.md: add **Role prompt** and **Anchor** (six literals, twice rule, style split; no per-role assignment table); amend **Role overlay** and **Next action** for `prompt:`/`also_prompt:`. Verify: `grep -n -E '\*\*(Role prompt|Anchor)\*\*' CONTEXT.md`.
- [ ] 3.4 `openspec/config.yaml` `context:` names `scripts/roles/<role>.md` (engine prompts, printed before the store's overlay) and the style split. Verify: `grep -n 'scripts/roles' openspec/config.yaml`.

## 4. Release

- [ ] 4.1 `atlas bump skill openspec-orchestrator --minor -m "Add literal engine role prompts with six repeated anchors; next prints prompt: before overlay:"` — never hand-edit releases.json. Verify: `git diff releases.json` shows exactly one new minor version entry relative to `main`.
