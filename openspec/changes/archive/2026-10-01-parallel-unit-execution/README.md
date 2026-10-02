# parallel-unit-execution

True parallel execution: generator splits tasks.md into independent units with recorded dependencies; one worktree+branch+subagent per unit; acceptance checks (unit tests, Playwright screenshot invariants for UI) written before implementing; implement→check→fix loop capped at 5 iterations with session logging; critic reviews only green units and inspects screenshots; merger agent rebases in dependency order, reruns the suite, squash-merges after Gate approval
