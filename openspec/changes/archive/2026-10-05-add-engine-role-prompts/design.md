# Design

`<engine>` = the engine checkout's absolute root (the directory holding `scripts/`).

### D1. Prompt text lives in files under `scripts/roles/`

- `scripts/roles/<role>.md`, one per `ROLES` entry. `role_prompt <role>` (lib.sh) validates the role against `ROLES` (same error text as `role_overlay`) and echoes `$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/roles/<role>.md`, erroring if the file is missing — resolved from lib.sh's own location, so the path is right whatever the caller's cwd. A missing prompt file is an incomplete engine checkout: `next` (under `set -e`) exits non-zero rather than omitting `prompt:`; untested, since the test would delete an engine file.
- Rejected: heredocs in lib.sh — prompt edits become shell-quoting edits (`'`, `` ` ``, `$` all appear in the texts), lib.sh grows by ~80 lines of prose, and the tests would need to call a function to read text that a file read gives directly.
- Rejected: a top-level `roles/` directory — reads as the store's `openspec/roles/` overlays; `scripts/` is where engine-owned runtime artifacts already live.

### D2. `next` prints a path line; `roles prompt` prints the text

- `emit_overlay` becomes `emit_role_lines <slug> <action>`: for a role-bearing action it prints `prompt: <path>` then, if present, `overlay: <path>`. Both `emit` and `_na_emit` already call it last, so `prompt:` lands right after `reason:` and before `overlay:`; no existing line moves. The `check` branch prints `also_prompt: $(role_prompt verifier)` after `also_model:`, before the existing `also_overlay:` block.
- Rejected: inlining the prompt text in `next` output — every `next` line is `key: value` on one line; multi-line text breaks `sed -n 's/^key: //p'` consumers and `check_line`, and makes `next` output 10–20× longer on every call, including `wait` loops.
- Rejected: a separate `emit_prompt` called beside `emit_overlay` in each emitter — the prompt-before-overlay order would then be restated at every call site.
- `cmd_roles_prompt` (run-change): `cat "$(role_prompt "$ROLE")"`; if `role_overlay` returns a path, `printf '\n'` then `cat` it. `--store` is required, as for `roles get`. This puts "engine prompt first, overlay after" in code, not in the orchestrator's paraphrase. `roles get` is untouched (overlay text only).
- Rejected: `roles prompt` printing only the engine text and leaving concatenation to the orchestrator — the order would again depend on the orchestrator.
- The orchestrator's dispatch for a role = `roles prompt` output, then (checkers) the `input:` lines from `model critic|verify` verbatim, then the step's own material. `next`'s `prompt:` path is what it reads when it does not shell out.

### D3. Anchors: fixed set, fixed per-role assignment, twice per prompt

| role | anchors |
|------|---------|
| proposer | `seam`, `generator/checker split`, `smallest tier that can be wrong safely`, `turns, not tokens` |
| critic | `fresh read`, `generator/checker split`, `seam`, `turns, not tokens` |
| worker | `seam`, `the engine records, the worker never asserts`, `turns, not tokens` |
| unit-critic | `fresh read`, `generator/checker split`, `the engine records, the worker never asserts`, `turns, not tokens` |
| verifier | `fresh read`, `generator/checker split`, `seam`, `the engine records, the worker never asserts`, `turns, not tokens` |

- Placement: line 1 (the opening line) names every assigned anchor once; the last line (exit/pass criterion) names every assigned anchor once; body lines name none. `seam` is counted as a whole word excluding `<seam>` placeholders (so `seams`, `file-list`, and the quoted `<seam>=<file>` syntax do not count; body text says "file list" instead); the others with `grep -oF`, lowercase.
- `fresh read` is the literal for the request's "fresh read / checker input contract" anchor: the checker input contract already reaches the checker verbatim as `input:` lines, so the prompt names the disposition and points at those lines rather than spending a second phrase.
- `smallest tier that can be wrong safely` is assigned to the proposer only: its classification decides fast path versus `full`, the only tier choice an agent (not `next_action`) makes.
- Rejected: three repetitions, or an anchor per rule line — the request fixes density at two; more is noise the hard rule exists to prevent.
- Rejected: storing the anchor table in lib.sh — nothing at runtime reads it; it would be a constant whose only caller is the test. The per-role table lives in the spec and `tests/run.sh` (enforced) only; CONTEXT.md **Anchor** carries the six literals, the twice rule, and the style split, not the assignment.

### D4. Prompt shape and content

- ≤20 lines, one rule per line, no headings, no blank lines. Line 1: role identity + anchors. Body: the role's invariants quoted verbatim from AUTONOMOUS-ORCHESTRATION.md / `checker_inputs` (the strings in the spec's first requirement are the tested subset), what to write and where, the result values `next` reads. Last line: the exit/pass criterion + anchors.
- Engine text precedes the overlay; the overlay cannot override anything in it (unchanged rule: "An overlay adds; it never overrides").
- Per-role body content, sources in brackets:
  - proposer: four-pillar classification + Guardrails line; four artifacts; seam list via `state set ... seams "<seam>=<file>,<file>;<seam>=<file>"`; `--store <slug>` on every OpenSpec CLI call, never `openspec init`; `validate --strict`; never lowers its own scrutiny [Phases step 3, SKILL.md Step 3].
  - critic: inputs = `input:` lines, never the generator's transcript; five standards; binary severity; `request` for a contradictory request; report path and result values; reappearing closed findings; no advisor, read-only [Phases step 3, Checker loops].
  - worker: covers unit worker, fixer, sweep, merge-conflict agent, split; checks first then `unit checks-done`; `unit iterate`, cap 5; `` `git add -- <files>`, never `-A` ``, trailers, never edits tasks.md; a file outside its list is a mid-run finding, not a silent edit; fixer changes only what findings name; one `advisor request` before failing; return instead of saving progress [Unit workers, Isolation, Fix rounds, Advisor].
  - unit-critic: inputs; read the checks diff to `checks_commit` and the iterate log the engine wrote; quote the recorded `screenshot` path verbatim for a UI unit; report `<name>.units/<unit>.critique.md`; no advisor, read-only [Unit critique, Checker loops].
  - verifier: worked example below.

Worked example — `scripts/roles/verifier.md` (13 lines; each assigned anchor 2×, line 1 and line 13; no `smallest tier…`):

```
You are Verify, a fresh read on the checker side of the generator/checker split: grade each seam of the committed change against the proposal; the engine records, the worker never asserts; turns, not tokens.
Your inputs are the `input:` lines printed with your model id. Open any other file only to confirm a file-list or dependency claim; never the generator's transcript.
The full gate may still be running beside you. Never state its result; `next` combines the engine's recorded gate result with yours.
Take no advice: never call `advisor request`. Write nothing but your report: no file edits, no git command that writes.
Grade every delta-spec requirement and the Guardrails line against the branch diff; a diff that introduces what Guardrails forbids is `blocking`.
`blocking`: a requirement the code does not meet, a file list naming a wrong file, a part of the request the spec skips, an approach you cannot see how to verify or see a concrete way to fail.
`warning`: correct, but breaks the hard rule "written for agents", rebuilds a seconds-long artifact per test or per file, or leaves the store's `config.yaml` behind an `orchestration.*` key, role overlay, or convention the change introduced.
`spec`: the proposal itself is wrong, ambiguous, or silent on what the code does, including a requirement left manual when a programmatic proxy exists.
You assign severity; the fixer does not reclassify.
Each finding: an id, the proposal requirement, `file:line`, what is wrong, what would satisfy it, and the severity.
Name every finding a prior report marked closed that reappears.
Write `<store>/.orchestration/state/<name>.verify.md` (overwrite) and return one result: `clean`, `warnings:<m>`, `blocking:<n>`, or `spec`.
Pass is not yours to claim: the engine records, the worker never asserts — the recorded full gate green plus zero `blocking` from this fresh read, every seam graded, the generator/checker split kept, in turns, not tokens.
```

### D5. Style split, documented where an editor will look

- AUTONOMOUS-ORCHESTRATION.md **Hard rule: written for agents** gains one bullet: inside agent-facing dispatch text (`scripts/roles/*.md`) anchor repetition wins and is not deduplicated; in human-facing prose terseness wins. The "Keep it short" bullet is the one an editor would otherwise apply to the prompts, so the exception sits beside it.
- **Role overlays** gains: the engine's role prompts are `scripts/roles/<role>.md`; `next` prints `prompt:` (and `also_prompt:`); `roles prompt` prints engine prompt then overlay. **Driving the loop** lists the two new lines; **Unit workers** names the worker prompt in the dispatch. CONTEXT.md adds **Role prompt** and **Anchor** (the six literals, the twice rule, the style split; no per-role table) and amends **Role overlay** / **Next action**. `openspec/config.yaml` `context:` names `scripts/roles/<role>.md` and the style split, so Verify's config-drift input sees it reflected.
- Rejected: stating the split only in CONTEXT.md — CONTEXT.md is vocabulary; the rule an editor applies while trimming lives in the Hard rule section.
- Existing invariant sentences (e.g. "Pick the smallest tier that can be wrong safely.", "Turns, not tokens, are the cost.") are left as worded; prompts quote them, docs do not change them.
