# Cursor agent capabilities (for porting a Claude Code skill)

Researched 2026-10-06 against cursor.com/docs. Docs pages show no publication date; dated claims come from the [CLI changelog](https://cursor.com/docs/cli/changelog) (latest entry seen: v2026.09.28).

| Capability | Supported? | How | Source |
|---|---|---|---|
| SKILL.md skills | Yes | `.cursor/skills/`, `.agents/skills/`, plus legacy `.claude/skills/`, `~/.claude/skills/` | [Skills](https://cursor.com/docs/context/skills) |
| Subagents, parallel | Yes | Built-in + custom `.cursor/agents/*.md`; reads `.claude/agents/` | [Subagents](https://cursor.com/docs/context/subagents) |
| Worktree isolation | Yes | Subagent "own environment"; CLI `-w/--worktree` | [Subagents](https://cursor.com/docs/context/subagents), [CLI params](https://cursor.com/docs/cli/reference/parameters) |
| Per-subagent model | Yes | `model:` frontmatter in agent file | [Subagents](https://cursor.com/docs/context/subagents) |
| Per-skill model | Not documented | — | [Skills](https://cursor.com/docs/context/skills) |
| Multiple-choice ask | Yes | Built-in ask-questions tool; ACP `cursor/ask_question` | [Agent overview](https://cursor.com/docs/agent/overview), [ACP](https://cursor.com/docs/cli/acp) |
| Background shell | Partial | User-driven (Ctrl+B ×2); background subagents | [CLI changelog](https://cursor.com/docs/cli/changelog) |
| Agent-set command timeout | Not documented | Timeouts exist but no documented agent parameter | [CLI changelog](https://cursor.com/docs/cli/changelog) |
| Headless CLI | Yes | `agent -p --model … --output-format …` | [Headless](https://cursor.com/docs/cli/headless) |
| Rules / AGENTS.md | Yes | `.cursor/rules/*.mdc`, `AGENTS.md` (nested), CLI also reads `CLAUDE.md` | [Rules](https://cursor.com/docs/context/rules), [Using CLI](https://cursor.com/docs/cli/using) |

## 1. Agent Skills

Cursor loads `SKILL.md` skills from project `.agents/skills/` and `.cursor/skills/`, user `~/.agents/skills/` and `~/.cursor/skills/`, and, for compatibility, `.claude/skills/`, `.codex/skills/`, `~/.claude/skills/`, `~/.codex/skills/`. Nested subdirectories are allowed ([Skills](https://cursor.com/docs/context/skills); nested discovery everywhere per [changelog](https://cursor.com/docs/cli/changelog), May 14 2026).

Frontmatter honored: `name` (required), `description` (required), `paths`, `disable-model-invocation`, `icon`, `color`, `metadata`. Claude-specific fields such as `allowed-tools` or `model` are not listed — not documented whether they are ignored or rejected.

Triggering: automatic by description relevance, manual via `/` in chat, or session-wide as a Custom Mode. `disable-model-invocation: true` restricts to manual ([Skills](https://cursor.com/docs/context/skills)).

## 2. Subagents

The agent delegates to subagents automatically and can run several concurrently. Built-ins: Explore, Bash, Browser. Custom subagents are Markdown files with YAML frontmatter in `.cursor/agents/` or `~/.cursor/agents/`; `.claude/agents/` is also read, `.cursor/` wins on name conflicts. Fields: `name`, `description`, `model`, `readonly`, `is_background`. Asking for "its own environment" runs a subagent in an isolated git worktree on its own branch ([Subagents](https://cursor.com/docs/context/subagents)).

Changelog: subagents inherit credentials, rules and approval policies (May 20 2026); single-turn (`-p`) runs wait for subagents to finish (v2026.08.11) ([changelog](https://cursor.com/docs/cli/changelog)).

Not documented: an explicit tool-call API (equivalent of Claude Code's `Agent` tool with a prompt and `subagent_type`); dispatch is described in natural language.

## 3. Model selection

Subagent files accept `model: inherit` (default) or a model ID with optional parameters, e.g. `[effort=high,context=300k]` ([Subagents](https://cursor.com/docs/context/subagents)). Skill frontmatter has no model field ([Skills](https://cursor.com/docs/context/skills)). CLI: `--model` ([parameters](https://cursor.com/docs/cli/reference/parameters)); model variants with parameters work headless (May 14 2026) and team model restrictions make the CLI exit (v2026.08.26) ([changelog](https://cursor.com/docs/cli/changelog)). Cursor model IDs differ from Claude Code tier aliases (`opus`/`sonnet`/`haiku`); exact ID list not checked here.

## 4. Ask-the-user tool

The agent can "ask clarifying questions during a task" and keeps working while waiting ([Agent overview](https://cursor.com/docs/agent/overview)). Native question UI with a freeform "Other" option (January 2026, [changelog](https://cursor.com/docs/cli/changelog)). Over ACP, `cursor/ask_question` is a blocking request with a title and questions, each with options and single/multi-select; the client returns answers, skipped, or cancelled ([ACP](https://cursor.com/docs/cli/acp)). `cursor/create_plan` is a blocking plan-approval request ([ACP](https://cursor.com/docs/cli/acp)). Behavior in `-p` headless mode: not documented.

## 5. Background shell and timeouts

The agent runs shell commands and monitors output under a Run Mode that governs approval and sandboxing ([Terminal](https://cursor.com/docs/agent/tools/terminal)). Changelog ([CLI changelog](https://cursor.com/docs/cli/changelog)):

- April 2026: double Ctrl+B sends a running shell to the background; headless runs wait for background work.
- v2026.08.26: shell monitoring advances when output matches a watched pattern rather than waiting for timeout.
- v2026.09.28: on timeout, the agent gets the path, size and line count of the output file.

Not documented: a timeout value or a run-in-background flag the agent sets per command, and the default timeout. Shell Mode (user-typed commands) times out at 30 s, not configurable ([Shell Mode](https://cursor.com/docs/cli/shell-mode)). Background subagents (`is_background: true`) are the documented way to keep long work off the main thread.

Unverified leads (forum): agent commands reportedly stopped around 10 minutes ([forum](https://forum.cursor.com/t/agent-was-interrupted-after-working-in-the-console-for-a-long-time/147476), [forum](https://forum.cursor.com/t/timeout-setting-on-terminal-shell-agent-tool/148885)).

## 6. Cursor CLI

Binary is `agent`. Flags ([parameters](https://cursor.com/docs/cli/reference/parameters), [headless](https://cursor.com/docs/cli/headless)): `-p/--print` (non-interactive, all tools incl. write and shell), `--output-format text|json|stream-json`, `--stream-partial-output`, `--model`, `--mode plan|ask`, `-f/--force`/`--yolo`, `--sandbox enabled|disabled`, `-w/--worktree [name]` (under `~/.cursor/worktrees/<repo>/<name>`), `--resume [chatId]`, `--continue`, `--workspace`, `--api-key` / `CURSOR_API_KEY`, `-H/--header`. `--trust` for worktree setup (v2026.08.11, [changelog](https://cursor.com/docs/cli/changelog)).

The CLI uses the same `.cursor/rules`, reads root `AGENTS.md` and `CLAUDE.md` as rules, honors `mcp.json`, and exposes skills via `/` ([Using CLI](https://cursor.com/docs/cli/using)). Whether skills auto-trigger in `-p` mode: not documented.

## 7. Rules and AGENTS.md

Project rules: `.cursor/rules/*.mdc` with frontmatter `description`, `globs`, `alwaysApply`. Also user rules (Customize → Rules, Agent chat only), team rules, and plain-Markdown `AGENTS.md`, with nested `AGENTS.md` applying to subdirectories and more specific files winning ([Rules](https://cursor.com/docs/context/rules)). The editor rules page does not mention `CLAUDE.md`; the CLI reads it ([Using CLI](https://cursor.com/docs/cli/using)).

## Implications for porting

- The skill can stay in place: Cursor reads `.claude/skills/` and `~/.claude/skills/`, so no copy is needed. Keep to `name`/`description` frontmatter; don't count on Claude-only fields.
- Express model tiers as custom subagent files (`.cursor/agents/*.md` with `model:`), not in SKILL.md. `.claude/agents/` is read too, but Cursor model IDs differ from Claude aliases, so tier mapping needs Cursor-specific files or a per-tool table.
- Subagent dispatch is described in prose, so SKILL.md text that names Claude's `Agent` tool and its parameters should be rephrased neutrally ("dispatch a subagent named X").
- Ask-user maps onto Cursor's native question tool; word it as "ask the user a multiple-choice question" rather than naming `AskUserQuestion`.
- Per-command timeouts and agent-started background shells are the weakest match. For long gates, prefer wrapping commands with an explicit `timeout`/`gtimeout` in the shell, or run them in a background subagent.
- Headless: `agent -p --force --model <id> --output-format stream-json`, with `-w` for isolation.
