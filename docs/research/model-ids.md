# Model IDs for agent `model:` fields

Collected 2026-10-09 from official docs. Excludes models retired or retiring before 2026-11. "Not documented" means the source page gives no exact string.

## Claude Code

Aliases: `default`, `best`, `fable`, `opus`, `sonnet`, `haiku`, `opus[1m]`, `sonnet[1m]`, `opusplan`. On the Anthropic API they resolve to: `opus` → Opus 5.5, `sonnet` → Sonnet 5.5, `haiku` → Haiku 5.5, `fable` → Fable 5.1. Other providers resolve them to older models. For example, Bedrock maps `sonnet` to 4.5.

| Family | Version | ID | Retirement | Note |
|---|---|---|---|---|
| Fable | 5.1 | `claude-fable-5-1` | not before 2027-09-01 | most capable, slowest |
| Opus | 5.5 | `claude-opus-5-5` | not before 2027-09-22 | default recommendation |
| Sonnet | 5.5 | `claude-sonnet-5-5` | not before 2027-09-28 | speed/intelligence balance |
| Haiku | 5.5 | `claude-haiku-5-5` | not before 2027-10-07 | fastest, cheapest |
| Fable | 5 | `claude-fable-5` | legacy, no date | |
| Opus | 5 | exact ID not documented | legacy | |
| Sonnet | 5 | `claude-sonnet-5` | legacy | |
| Opus | 4.8 / 4.6 | `claude-opus-4-8`, `claude-opus-4-6` | legacy | |
| Sonnet | 4.6 / 4.5 | `claude-sonnet-4-6`, `claude-sonnet-4-5` (`claude-sonnet-4-5-20250929`) | legacy | |
| Haiku | 4.5 | `claude-haiku-4-5` | legacy | |

GPT and Gemini are not offered.

## Cursor (`.cursor/agents/*.md` `model:`, `agent --model`)

`model:` takes `inherit` (the default) or a model ID, optionally followed by bracketed params. Documented examples: `gpt-5.6-sol`, `claude-opus-5[effort=high]`, `claude-opus-5[context=300k]`. The models page names most models without giving their IDs. Gemini IDs are not documented.

| Family | Version | ID | Note |
|---|---|---|---|
| Claude Opus | 5.5 | not documented. Fast mode: `claude-opus-5-5-fast` | 20% cheaper than Opus 5 |
| Claude Opus | 5 | `claude-opus-5`. Fast mode: `claude-opus-5-fast` | |
| Claude Opus | 4.8 | not documented. Fast mode: `claude-opus-4-8-fast` | |
| Claude Fable | 5.1, 5 | not documented | about 2-2.5x Opus cost, most capable |
| Claude Sonnet | 5.5, 5 | not documented | |
| Claude Haiku | 5.5 | not documented | cheap below 100k input |
| GPT | 5.6 Sol | `gpt-5.6-sol` | top of the 5.6 line |
| GPT | 5.6 Terra / Luna | not documented | mid tier / smallest |
| GPT | 5.5, 5.4 (+mini/nano), 5.3 Codex, 5.2 | not documented. Variants: `gpt-5.3-codex-high`, `gpt-5.2-high` | |
| GPT | 5 | variants `gpt-5-high`, `gpt-5-high-fast`, `gpt-5-low-fast` | legacy |
| Gemini | 3.8 Flash, 3.1 Pro, others | not documented | |

No retirement dates are listed.

## GitHub Copilot (VS Code custom agents)

The `model:` field takes a display name (string or prioritized array). Example from the docs: `model: ['Claude Opus 4.5', 'GPT-5.2']`. The `Name (vendor)` form, e.g. `GPT-5.2 (copilot)`, is documented only for `handoffs.model`. All of the models below are GA and none has a retirement date.

| Family | Display names (exact) | Note |
|---|---|---|
| Claude | `Claude Fable 5.1`, `Claude Fable 5` | admin must enable; most capable |
| Claude | `Claude Opus 5.5`, `Claude Opus 5`, `Claude Opus 4.8`, `Claude Opus 4.8 (fast mode) (preview)` | |
| Claude | `Claude Sonnet 5.5`, `Claude Sonnet 5`, `Claude Sonnet 4.6` | |
| Claude | `Claude Haiku 5.5`, `Claude Haiku 4.5` | fast/cheap |
| GPT | `GPT-6.1 Sol`, `GPT-6 Astra`, `GPT-6 Sol`, `GPT-6 Luna` | |
| GPT | `GPT-5.6 Sol`, `GPT-5.6 Terra`, `GPT-5.6 Luna`, `GPT-5.5`, `GPT-5.4`, `GPT-5.4 mini`, `GPT-5.4 nano`, `GPT-5.3-Codex`, `GPT-5 mini` | |
| Gemini | `Gemini 3.8 Flash`, `Gemini 3.7 Flash` | fast |

## OpenAI Codex CLI

Codex offers no Claude or Gemini models.

| Family | Version | ID | Retirement | Note |
|---|---|---|---|---|
| GPT | 6 Astra | `gpt-6-astra` | none | most capable |
| GPT | 6.1 Sol | `gpt-6.1-sol` | none | near-Astra, cheaper |
| GPT | 6 Sol | `gpt-6-sol` | none | named only as a replacement, not in the CLI table |
| GPT | 6 Luna | `gpt-6-luna` | none | most efficient, high volume |

Excluded: `gpt-5.5` (retires 2026-10-14), `gpt-5.4` and `gpt-5.4-mini` (retired), `gpt-5.3-codex-spark` (retired). `gpt-5.2` and `gpt-5.3-codex` are deprecated for ChatGPT sign-in.

## OpenCode (`provider/model`)

The format is `provider_id/model_id`. The opencode.ai example is `anthropic/claude-sonnet-4-20250514`. The IDs below come from the models.dev provider pages, which list no deprecation status.

| Provider | IDs |
|---|---|
| anthropic | `anthropic/claude-fable-5-1`, `anthropic/claude-fable-5`, `anthropic/claude-mythos-5`, `anthropic/claude-opus-5-5`, `anthropic/claude-opus-5`, `anthropic/claude-opus-4-8`, `anthropic/claude-opus-4-7`, `anthropic/claude-opus-4-6`, `anthropic/claude-opus-4-5`, `anthropic/claude-sonnet-5-5`, `anthropic/claude-sonnet-5`, `anthropic/claude-sonnet-4-6`, `anthropic/claude-haiku-5-5` |
| openai | `openai/gpt-6.1-sol`, `openai/gpt-6-astra`, `openai/gpt-6-astra-fast`, `openai/gpt-6-sol`, `openai/gpt-6-luna`, `openai/gpt-5.6-sol`, `openai/gpt-5.6-terra`, `openai/gpt-5.6-luna`, `openai/gpt-5.6-cyber`, `openai/gpt-5.5`, `openai/gpt-5.5-pro`, `openai/gpt-5.5-instant`, `openai/gpt-5.4`, `openai/gpt-5.4-pro`, `openai/gpt-5.4-mini`, `openai/gpt-5.4-nano` |

Gemini IDs were not checked (google provider page not fetched).

## Symlinks (skills dirs, agent files)

| Tool | Status |
|---|---|
| Claude Code | Not documented for skills or agents. Symlinks are documented only for `.claude/rules/`. Issues report that symlinked skill dirs work, but `~/.claude/skills` as a symlink regressed around v2.1.69 (issue closed). |
| Cursor | Not documented. Forum reports: works on desktop, not on Cloud Agent web UI, and not surfaced in SDK local agents. |
| Copilot / VS Code | Not documented. |
| Codex CLI | Documented: follows symlinked skill folders. |
| OpenCode | Not documented. |

## Sources

- https://code.claude.com/docs/en/model-config (no date shown)
- https://platform.claude.com/docs/en/about-claude/models/overview (no date shown)
- https://cursor.com/docs/models (no date)
- https://cursor.com/docs/subagents (no date)
- https://docs.github.com/en/copilot/reference/ai-models/supported-models (no date; read the first 100k chars)
- https://code.visualstudio.com/docs/copilot/customization/custom-agents (2026-10-07)
- https://learn.chatgpt.com/docs/models (redirected from developers.openai.com/codex/models; no date)
- https://developers.openai.com/codex/skills (symlinks)
- https://opencode.ai/docs/models (last updated 2026-10-08)
- https://models.dev/anthropic, https://models.dev/openai
- https://github.com/anthropics/claude-code/issues/37590, https://claudeissues.com/issue/38051-user-level-skills-not-loaded-when-claude-skills-is-a-symlink-regression-since-v2
- https://forum.cursor.com/t/symlink-support-for-skills-missing-in-cursor-cloud-agent/153603, https://forum.cursor.com/t/cursor-sdk-local-agents-mis-scope-project-skills-for-git-subdirectories-and-symlinked-skill-layouts/161855
