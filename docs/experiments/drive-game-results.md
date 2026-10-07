# Drive game — results

Same prompt per round ([v1](drive-game-prompt.md), [v2](drive-game-v2-prompt.md)), separate
empty folders, sequential runs, all on 2026-10-05/06 UTC. Times from session transcripts
and store session logs; test counts from a fresh `npm test` run afterwards.

## Caveats that apply to every row

- **Top-level model differed.** The raw run used Fable 5.1; every orchestrator run used
  Opus 5.5 as its own session model (sub-agents followed the tier table). The one-variable
  rule was not met in any round.
- **The raw run's folder was first named `test-sdd`**, renamed to `test-fable` for v2.
- **No independent review has been run on these two repos.** Product rows are
  self-measured (fresh `npm test`, static counts). A third v1 run, an orchestrator on a
  prose-only install, was reviewed and is excluded here; its findings fed releases 1.9.0
  and 1.12.0 and are recorded in those commits.

## v1 — build the game from an empty folder

| | Raw Fable (`test-fable`) | Orchestrator 1.12 + grill (`test-grill`) |
|---|---|---|
| Engine commit | – | 49a21f2 |
| Started (UTC) | 10-05 20:46 | 10-06 11:40 |
| Wall clock to merge | 23 min | 215 min |
| Human wait | 0 | 110 min, 7 stops (root, grill, Gate 0, Gate 1 ×3, manual, Gate 2) |
| Machine time | 23 min | ~105 min |
| Grill | – | 1 round, 5 questions, "all recommended" in 70 s; glossary 9 terms, ADR 0001 stack, ADR 0002 flat world |
| Pillars | – | seams / project / new / runtime |
| Sub-agents | 0 | 22 |
| Model-minutes active | Fable 23 | Opus 113, Sonnet ~79, Fable 22 |
| Output tokens | 191K | 191K + 485K sub-agents |
| Unit tiers | – | 3 deep, 5 standard |
| Unit critics | – | 3 Fable, 5 Opus |
| Unit iterations | – | 22, 5 red, one unit at the cap |
| Verify rounds | – | 3 (spec → spec → clean) |
| Fix rounds | – | 2 |
| Source lines / files | 1,882 / 22 | 2,409 / 23 |
| Map JSON lines | 88 | 863 |
| Unit tests (files) | 32 (4) | 81 (7) |
| Playwright tests | 4 | 1 |
| README lines | 80 | 57 |
| Fresh `npm test` | pass, knip clean | pass, knip clean |
| Toolchain | vite 6, 1 critical audit finding | current, pinned |

### v1 review

The raw run was reviewed (not blind) against the excluded prose-only run: all 12 checklist
items passed; defects 1 major (npm audit, critical) + 5 minor (rebind unbinds the other
action, a weak "both maps" e2e, `postinstall` download, unused `dt`, asphalt ≈ tarmac
visually). `test-grill` v1 was not reviewed; the collision gap below was found by hand.

### v1 findings

- `test-grill`: **the car drove through buildings and trees.** The brief said "static
  buildings" and "realistic"; no artifact named collision; grill asked five how-questions;
  the critic's Fidelity read "nothing beyond the request"; every checker passed a silent
  proposal. The raw run added building collision unasked. → 1.14.0.
- `test-grill`: a Sonnet unit worker hung 142 min on a gate command; the unit was rescued
  by an Opus revise and merged, so the critical path was unaffected, but it is most of the
  Sonnet column. → 1.13.0 (`gate_timeout`, written by that session).
- `test-grill`: Verify round 3 ran on Sonnet because the round-2 fixer was `mechanical` and
  the tier-above rule picked `standard`. Open: a `deep` floor for Verify.
- `test-grill`: three Gate 1 stops; the 53-minute wait on the first spec amendment is the
  largest single human-time item in the experiment.

## v2 — day/night, lights, speed steering, collision, hills

| | Raw Fable (`test-fable`) | Orchestrator 1.14 + grill (`test-grill`) |
|---|---|---|
| Engine commit | – | c87993d |
| Started (UTC) | 10-06 20:17 | 10-06 16:45 |
| Wall clock to merge | 30 min | 199 min |
| Human wait | 0 | 55 min, 3 stops (grill 1 min, Gate 0 45 min, Gate 1 8 min; Gate 2 5 s) |
| Machine time | 30 min | ~144 min |
| Grill | – | 1 question (cockpit steering display), nothing obvious asked; ADR 0003 graded roads supersedes flat-world |
| Pillars | – | seams / project / new / none |
| Sub-agents | 0 | 14 |
| Model-minutes | Fable 30 | Sonnet 104, Opus 79, Fable 20, Haiku 2 |
| Output tokens | 195K | 98K + 514K sub-agents |
| Unit tiers | – | terrain deep (2 dependents); daylight, vehicle, shell standard |
| Critique | – | 2 rounds, 3 warnings swept by Haiku |
| Unit loop | – | vehicle: 5 reds on hill suspension → advisor → Gate 1 → retry green |
| Verify | – | blocking:1 → fix (standard) → clean |
| v2 diff | +1,047 / −81, 25 files | +2,171 / −312, 22 files |
| Unit tests after v2 | 59 (from 32) | 117 (from 81) |
| Playwright tests | 9 (4 v1 + 5 v2) | 7 (1 v1 + 6 v2) |
| Required v2 screenshots | all 4, plus one per map | all 4 |
| README lines | 119 | 77 |
| Fresh `npm test` | 1 Playwright failure, flake (time-based distance assertion; passes alone, twice) | all green |

### v2 findings

- Grill with the implied-baseline rule asked exactly one question, a real design fork, and
  wrote the ADR that made the hills item finished design (graded roads, shoulders) rather
  than a height function.
- The vehicle unit went red five times before anyone asked for help; the human answer at
  Gate 1 ("add terrain bumps") is one a deep model gives in a minute. → 1.15.0 (advisor
  mandatory at the second consecutive red; red after advice → Gate 1; spec contradiction →
  Gate 1 at first red).
- The shell UI worker ran 349 turns / 50 min for one unit. Open.
- The raw run's time-based e2e assertion is the kind the orchestrator's critic blocks.
- The raw run added a desert-map regression e2e the orchestrator did not think to.

## Engine changes this experiment produced

| Version | Change | Triggered by |
|---|---|---|
| 1.9.0 | Ship the engine with the skill (directory install) | excluded prose-only run (no `run-change` calls) |
| 1.11.0 | classify → grill unless trivial → propose | excluded run's dependency chain nobody saw |
| 1.12.0 | Foundation = two or more dependents; `gate_ui` | excluded run: 7 deep units, Playwright per iterate |
| 1.13.0 | `gate_timeout`, timeouts on background commands | v1 `test-grill` 142-min hang |
| 1.14.0 | Implied baseline is part of the request; never ask the obvious | v1 `test-grill` car through walls |
| 1.15.0 | Advisor at second red; red-after-advice and spec contradiction → Gate 1 | v2 `test-grill` five reds |

## Still open

- Fable as the orchestrator's own model, to close the one-variable gap.
- A `deep` floor for Verify regardless of the fixer's tier.
- A blind review of both repos with the v1 and v2 checklists (collision item included).
- Turn budget or checkpoint for a single UI unit worker.
