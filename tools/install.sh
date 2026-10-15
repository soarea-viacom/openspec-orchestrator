#!/usr/bin/env bash
# Standalone install (no Atlas). Places the skill and one tool's agents in a
# single home, then links each into the tool's own directories, so every
# tool installed from this checkout reads the same files.
#   install.sh --tool <claude-code|cursor|copilot|codex|opencode>
#              [--project <dir>] [--copy] [--dry-run] [--uninstall]
set -euo pipefail
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOME_DIR="${OPENSPEC_ORCHESTRATOR_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/openspec-orchestrator}"
TOOL="" PROJECT="" MODE=link DRY=0 UNINSTALL=0
while [ $# -gt 0 ]; do
  case "$1" in
    --tool) TOOL="$2"; shift 2 ;;
    --project) PROJECT="$(cd "$2" && pwd)"; shift 2 ;;
    --copy) MODE=copy; shift ;;
    --dry-run) DRY=1; shift ;;
    --uninstall) UNINSTALL=1; shift ;;
    *) echo "unknown option $1" >&2; exit 2 ;;
  esac
done
[ -n "$TOOL" ] || { echo "--tool is required" >&2; exit 2; }

# ENTRY is the agent file name with NAME replaced. OpenCode's carries the
# -opencode suffix: that tool names an agent by its file and Atlas files it
# under the catalog key, so next prints the same name for both installs.
case "$TOOL:${PROJECT:+p}" in
  claude-code:)  SKILLS_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills"; AGENTS_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/agents"; ENTRY=NAME ;;
  claude-code:p) SKILLS_DIR="$PROJECT/.claude/skills"; AGENTS_DIR="$PROJECT/.claude/agents"; ENTRY=NAME ;;
  cursor:)       SKILLS_DIR="$HOME/.cursor/skills"; AGENTS_DIR="$HOME/.cursor/agents"; ENTRY=NAME.md ;;
  cursor:p)      SKILLS_DIR="$PROJECT/.cursor/skills"; AGENTS_DIR="$PROJECT/.cursor/agents"; ENTRY=NAME.md ;;
  copilot:)      SKILLS_DIR="$HOME/.copilot/skills"; AGENTS_DIR="$HOME/.copilot/agents"; ENTRY=NAME.agent.md ;;
  copilot:p)     SKILLS_DIR="$PROJECT/.github/skills"; AGENTS_DIR="$PROJECT/.github/agents"; ENTRY=NAME.agent.md ;;
  codex:)        SKILLS_DIR="$HOME/.codex/skills"; AGENTS_DIR="$HOME/.codex/agents"; ENTRY=NAME.toml ;;
  codex:p)       SKILLS_DIR="$PROJECT/.agents/skills"; AGENTS_DIR="$PROJECT/.codex/agents"; ENTRY=NAME.toml ;;
  opencode:)     SKILLS_DIR="$HOME/.config/opencode/skills"; AGENTS_DIR="$HOME/.config/opencode/agents"; ENTRY=NAME-opencode.md ;;
  opencode:p)    SKILLS_DIR="$PROJECT/.opencode/skills"; AGENTS_DIR="$PROJECT/.opencode/agents"; ENTRY=NAME-opencode.md ;;
  *) echo "unknown tool $TOOL" >&2; exit 2 ;;
esac

run() { if [ "$DRY" = 1 ]; then echo "$*"; else "$@"; fi; }

# A destination is ours only if it links into HOME_DIR or carries the
# marker a copy leaves; anything else is the user's and is left alone.
ours() { [ -L "$1" ] && case "$(readlink "$1")" in "$HOME_DIR"/*) return 0 ;; esac; [ -e "$1/.openspec-orchestrator" ] || [ -e "$1.openspec-orchestrator" ]; }
place() { # place <home path> <destination>
  if [ -e "$2" ] || [ -L "$2" ]; then
    ours "$2" || { echo "skip $2: exists and was not installed by this script" >&2; return 0; }
    run rm -rf "$2" "$2.openspec-orchestrator"
  fi
  run mkdir -p "$(dirname "$2")"
  if [ "$MODE" = link ]; then run ln -s "$1" "$2"
  else
    run cp -R "$1" "$2"
    if [ -d "$1" ]; then run touch "$2/.openspec-orchestrator"; else run touch "$2.openspec-orchestrator"; fi
  fi
}

agent_names() { for d in "$SRC/agents/$TOOL"/openspec-*/; do basename "$d"; done; }

if [ "$UNINSTALL" = 1 ]; then
  paths=("$SKILLS_DIR/openspec-orchestrator")
  for n in $(agent_names); do paths+=("$AGENTS_DIR/${ENTRY//NAME/$n}"); done
  for p in "${paths[@]}"; do
    if ours "$p"; then run rm -rf "$p" "$p.openspec-orchestrator"; fi
  done
  exit 0
fi

# Home: skill + this tool's agents, replaced whole on every install. It is
# this script's own copy, so a populated HOME_DIR must carry the marker a
# first install leaves or it is someone else's directory and is refused.
# Codex agents become TOML here, because Codex reads model and
# model_reasoning_effort as keys, not frontmatter.
if [ -e "$HOME_DIR" ] && [ ! -e "$HOME_DIR/.openspec-orchestrator" ] && [ -n "$(ls -A "$HOME_DIR" 2>/dev/null)" ]; then
  echo "refusing $HOME_DIR: exists, is not empty and was not created by this script" >&2; exit 1
fi
run mkdir -p "$HOME_DIR/agents"
run touch "$HOME_DIR/.openspec-orchestrator"
run rm -rf "$HOME_DIR/skill" "$HOME_DIR/agents/$TOOL"
run cp -R "$SRC/skills/openspec-orchestrator" "$HOME_DIR/skill"
run mkdir -p "$HOME_DIR/agents/$TOOL"
for n in $(agent_names); do
  src="$SRC/agents/$TOOL/$n/AGENT.md"
  case "$TOOL" in
    claude-code) run mkdir -p "$HOME_DIR/agents/$TOOL/$n"; run cp "$src" "$HOME_DIR/agents/$TOOL/$n/AGENT.md" ;;
    codex)
      if [ "$DRY" = 1 ]; then echo "write $HOME_DIR/agents/$TOOL/$n.toml"; else
        python3 - "$src" "$HOME_DIR/agents/$TOOL/$n.toml" <<'EOF'
import json, re, sys
text = open(sys.argv[1], encoding="utf-8").read()
m = re.match(r"---\n(.*?)\n---\n(.*)", text, re.S)
fm = dict(l.split(": ", 1) for l in m.group(1).splitlines())
q = lambda s: json.dumps(s, ensure_ascii=False)
out = [f"name = {q(fm['name'])}", f"description = {q(fm['description'])}", f"model = {q(fm['model'])}",
       f"model_reasoning_effort = {q(fm['effort'])}", "developer_instructions = '''", m.group(2).rstrip("\n"), "'''"]
open(sys.argv[2], "w", encoding="utf-8").write("\n".join(out) + "\n")
EOF
      fi ;;
    *) run cp "$src" "$HOME_DIR/agents/$TOOL/${ENTRY//NAME/$n}" ;;
  esac
done

place "$HOME_DIR/skill" "$SKILLS_DIR/openspec-orchestrator"
for n in $(agent_names); do
  e="${ENTRY//NAME/$n}"
  place "$HOME_DIR/agents/$TOOL/$e" "$AGENTS_DIR/$e"
done
echo "installed openspec-orchestrator for $TOOL ($MODE) from $HOME_DIR"
