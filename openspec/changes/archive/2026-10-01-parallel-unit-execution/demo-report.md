# chess-trio demo: parallel units vs single worker

Request: "Add a captured-pieces panel, a per-side move clock, and a board-flip button."
Same accepted proposal (post-Gate-1 amendment) for both runs; same trunk 89bad45; chess-game store, unit_concurrency 3.

| run | apply-start → gate2 | human wait (Gate 1) | machine time | units | iterations | max critic calls | verify rounds | fix rounds |
|---|---|---|---|---|---|---|---|---|
| chess-trio (parallel) | 69m03s | 12m54s | 56m09s | 4 (ui-hooks → 3 parallel) | 2+1+1+1 | 5 (ui-hooks twice) | 3 (spec → blocking:1 → clean) | 2 |
| chess-trio-single (baseline) | 43m03s | 0m37s | 42m26s | 1 | 1 | 1 | 3 (blocking:2 → blocking:2 → warnings:1) | 2 |

Phase breakdown (machine time):
- parallel units loop (split → units-merged): 30m33s. Critical path: ui-hooks spawn→green 10m14s, critique 4m31s, revise+re-iterate 2m03s, critique 2m15s (serial prefix 19m04s) → three features spawned together, longest to green 7m14s (board-flip), critiques finished 11m25s after spawn → merged 14:38:37.
- single unit loop: 21m26s (spawn→green 16m59s, critique 4m25s).
- checking (gate + Verify + fix rounds), excluding human wait: parallel 25m36s; single 21m00s.

Reading: the parallel run was slower end to end. The three feature units did overlap (7–11 min for all three vs. ~17 min for one worker doing everything), but the serial ui-hooks prefix (19 min incl. two max critiques) and one extra max critique per unit ate the gain, and the parallel run paid for discovering the proposal's gaps (Verify `spec`: UI tests silently skipped on the merged branch; four SHALLs without checks). The baseline inherited the amended proposal and the warm Playwright/npm caches, so it is biased in the baseline's favour. Per-unit critique at the max tier is the dominant fixed cost: ~2–4.5 min per call, 5 calls.

Where parallelism would pay: more than three independent features, or features whose implementation dominates the fixed per-unit costs (critique + spawn + npm ci).

Carried warnings at Gate 2 (parallel run): none blocking; unit critiques noted the clock labels/active style (fixed in the amendment round) and board-flip persistence coverage (fixed).
Engine defects found by the demo (follow-ups in the orchestrator repo): `units single` emits duplicate task ids (sub-task numbers like 1.2.1 collapse to 1.2) so `units check` refuses; a mechanical sweep logged with `phase proposed` shifts `model critic`'s tier (sweep entries must not use the proposer phase); the change-level worktree has no node_modules so UI tests skip on the merged-branch gate unless `npm ci` runs there (now in the amended proposal; worth an engine rule).
