#!/usr/bin/env bash
# Shared helpers for run-change/status. Sourced, not executed directly.
set -euo pipefail

REGISTRY="${OPENSPEC_STORE_REGISTRY:-$HOME/.local/share/openspec/stores/registry.yaml}"

# store_path <slug> -> absolute local_path for that store, from the CLI's
# own registry (there is no other source of truth for slug -> path).
store_path() {
  local slug="$1"
  [ -f "$REGISTRY" ] || { echo "no store registry at $REGISTRY" >&2; return 1; }
  awk -v slug="$slug" '
    $0 ~ "^  "slug":$" { found=1; next }
    found && /^  [a-zA-Z0-9_-]+:$/ { exit }
    found && /local_path:/ { sub(/.*local_path:[ ]*/, ""); print; exit }
  ' "$REGISTRY"
}

orchestration_dir() {
  local slug="$1"
  local path
  path="$(store_path "$slug")"
  [ -n "$path" ] || { echo "store '$slug' not found in $REGISTRY" >&2; return 1; }
  echo "$path/.orchestration"
}

# Orchestration config lives in the resolved store's openspec/config.yaml.
# In external mode the store's local_path is a separate directory
# (~/.local/share/openspec/stores/<slug>) from the project; in local mode (SKILL.md
# Step 1) the store's local_path IS the project itself, so this resolves
# to the project's own openspec/config.yaml. Either way there's exactly
# one config file per change, at whatever store_path() returns.
store_config() {
  local slug="$1"
  local path
  path="$(store_path "$slug")"
  [ -n "$path" ] || { echo "store '$slug' not found in $REGISTRY" >&2; return 1; }
  echo "$path/openspec/config.yaml"
}

# guard_project_openspec <store-slug> <project>: refuse only when the
# project has its own openspec/ folder AND the store this command is about
# to operate against points somewhere else entirely — that combination
# means the caller resolved the wrong store for a project that should be
# running in local mode (SKILL.md Step 1), and writing to the external
# store would silently diverge from the project's real artifacts. When the
# store's local_path IS the project (local mode: store setup was run with
# --path <project>), this is a no-op — the project's openspec/ folder is
# exactly the resolved root, by design.
guard_project_openspec() {
  local slug="$1" project="$2"
  local resolved; resolved="$(store_path "$slug")"
  [ "${resolved%/}" = "${project%/}" ] && return 0
  [ ! -e "$project/openspec" ] || {
    echo "refusing: $project contains an openspec/ folder but store '$slug' points elsewhere ($resolved) — this project should run in local mode against its own folder (see SKILL.md Step 1), not against a different external store" >&2
    return 1
  }
}

# ensure_project_git <project>: the branch/worktree model needs a repo with
# a commit on a trunk. An empty folder or a folder of un-tracked files (the
# first idea dropped into a new project) gets `git init -b main` and an
# initial commit of whatever is there. The only write under the project
# root the engine ever makes — .git/ is project infrastructure, not an
# OpenSpec artifact. Idempotent: an existing repo with a commit is untouched.
ensure_project_git() {
  local project="$1"
  if ! git -C "$project" rev-parse --git-dir >/dev/null 2>&1; then
    git init -q -b main "$project"
    echo "initialized git repo in $project (branch main)" >&2
  fi
  if ! git -C "$project" rev-parse --verify -q HEAD >/dev/null; then
    git -C "$project" add -A
    git -C "$project" commit -q --allow-empty -m "Initial commit"
    echo "created initial commit in $project" >&2
  fi
}

# trunk_ref <project> -> the ref to treat as trunk: origin/<trunk> when that
# remote ref exists, else the local trunk branch; trunk itself is
# origin/HEAD, else local main, else local master. Shared by merge-lane
# (merges this ref into the change branch) and the trunk preflight (runs
# gate_full against a detached worktree of this ref) so both test the same
# commit. No fetch here — neither caller fetches either; a stale
# origin/HEAD is the caller's problem, not this function's.
trunk_ref() {
  local project="$1"
  local trunk
  # || true: pipefail would abort the script before the fallback below
  # whenever origin/HEAD is unset (e.g. remote added without a fetch).
  trunk="$(git -C "$project" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#origin/##' || true)"
  if [ -z "$trunk" ]; then
    local t
    for t in main master; do
      git -C "$project" rev-parse --verify -q "refs/heads/$t" >/dev/null && { trunk="$t"; break; }
    done
  fi
  [ -n "$trunk" ] || { echo "cannot determine trunk for $project: no origin/HEAD and no local main or master" >&2; return 1; }
  # Prefer the remote-tracking trunk when the project has one; a local-only
  # project (no remote) uses its local trunk instead. Never invent a remote
  # ref that doesn't exist — that would fail late with a git error.
  local ref="origin/$trunk"
  git -C "$project" rev-parse --verify -q "refs/remotes/$ref" >/dev/null || ref="$trunk"
  echo "$ref"
}

# change_dir <store-slug> <name> -> absolute path to the change's artifact
# directory, resolved in order: the change's own worktree (where a branch
# still in flight keeps its openspec/changes/<name>/), that worktree's
# archive copy (date-prefixed — the CLI always archives under
# YYYY-MM-DD-<name>, so a bare *-<name> glob would also match an unrelated
# change whose name happens to end in "-<name>"), then the same two under
# the store's own local_path (external mode keeps nothing there until
# merge, but local mode's store IS the project, so this is where a merged
# or hand-maintained change's artifacts actually live). More than one
# archive match at a given base is an error, not a silent pick. No match
# anywhere -> non-zero, caller writes nothing.
change_dir() {
  local slug="$1" name="$2" base d matches
  for base in "$(workspace_path "$slug" "$name")" "$(store_path "$slug")"; do
    d="$base/openspec/changes/$name"
    [ -d "$d" ] && { echo "$d"; return 0; }
    matches=("$base"/openspec/changes/archive/[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-"$name")
    if [ -d "${matches[0]}" ]; then
      [ "${#matches[@]}" -eq 1 ] || { echo "more than one archived match for $name under $base" >&2; return 1; }
      echo "${matches[0]}"
      return 0
    fi
  done
  return 1
}

# checker_inputs <critic|verify> <store-slug> <name> -> static "input:"
# lines describing the checker's input contract: it reads no file itself,
# and the seam line names the `seams` field rather than resolving it, so
# this also works for `model critic --name <initiative>` (an initiative has
# no change state file to resolve against). The shared rule line is what
# stops a checker from re-reading the whole codebase — only follow a file
# to confirm a seam or dependency claim.
checker_inputs() {
  local role="$1" slug="$2" name="$3" unit="${4:-}"
  local seam_line
  seam_line="$(printf 'input: seam list — state get --store %s --name %s, field seams\n' "$slug" "$name")"
  if [ "$role" = unit-critic ]; then
    [ -n "$unit" ] || { echo "checker_inputs unit-critic requires a unit" >&2; return 1; }
    printf 'input: the proposal + delta spec\n'
    printf 'input: unit %s files and task ids — state get --store %s --name %s, fields units/unit_tasks\n' "$unit" "$slug" "$name"
    printf 'input: the unit diff from its base (git diff <base>..change/%s.%s)\n' "$name" "$unit"
    printf 'input: the checks diff to its checks_commit (git diff <base>..<checks_commit>)\n'
    printf 'input: its screenshots, as listed by units ready-for-review, opened with an image-capable read\n'
    printf 'input: the prior unit critique, if any\n'
    printf 'input: read other files only to confirm a seam is real or a dependency claim is true; never explore the codebase; never the generator'"'"'s transcript\n'
    return 0
  fi
  case "$role" in
    critic)
      printf 'input: the originating request\n'
      printf 'input: the draft delta spec (+ design.md)\n'
      printf '%s\n' "$seam_line"
      # Store-root paths, not the worktree: grill mode leaves these uncommitted in the root.
      printf 'input: the Project glossary, if present — %s/openspec/CONTEXT.md: a non-canonical term is one warning finding\n' "$(store_path "$slug")"
      printf 'input: the ADRs, if present — %s/openspec/adr/: a proposal contradicting an ADR is blocking unless it names the ADR it supersedes\n' "$(store_path "$slug")"
      ;;
    verify)
      printf 'input: the proposal + delta spec\n'
      printf '%s\n' "$seam_line"
      printf 'input: the branch diff\n'
      printf 'input: the store config — %s/openspec/config.yaml: a diff that adds or renames an orchestration.* key, a role overlay, or a convention the context block states must be reflected there, else one warning finding\n' "$(store_path "$slug")"
      ;;
    *) echo "unknown checker role '$role' (expected critic|verify|unit-critic)" >&2; return 1 ;;
  esac
  printf 'input: the prior %s report, if any\n' "$role"
  printf 'input: read other files only to confirm a seam is real or a dependency claim is true; never explore the codebase; never the generator'"'"'s transcript\n'
}

# concurrency_cap <store-slug> -> N from the store's openspec/config.yaml
# orchestration.concurrency, default 2: parallelism is gated by the
# disjoint-files check, not by this number, so a cap of 1 only ever
# serialised changes that could not have conflicted.
concurrency_cap() {
  local cfg
  cfg="$(store_config "$1")"
  local n
  n="$(awk '/^orchestration:/{f=1;next} f && /^[a-zA-Z]/{exit} f && /^[[:space:]]+concurrency:/{print $2; exit}' "$cfg" 2>/dev/null || true)"
  echo "${n:-2}"
}

gate_command() {
  local slug="$1" mode="$2" # quick|full -> reads orchestration.gate_quick / gate_full
  local cfg
  cfg="$(store_config "$slug")"
  local key="gate_${mode}"
  # A gate command is shell code, often containing double quotes of its own
  # (e.g. "$PWD"), so its YAML value is written single-quoted; strip a
  # matching pair of either quote style, never just the double-quote one.
  awk -v key="$key" '
    /^orchestration:/ { f=1; next }
    f && /^[a-zA-Z]/ { exit }
    f && index($0, key":") {
      sub(".*"key":[ ]*", "")
      line = $0
      if (line ~ /^".*"$/) { sub(/^"/, "", line); sub(/"$/, "", line) }
      else if (line ~ /^'"'"'.*'"'"'$/) { sub(/^'"'"'/, "", line); sub(/'"'"'$/, "", line) }
      print line; exit
    }
  ' "$cfg" 2>/dev/null || true
}

gate_timeout() {
  local cfg n
  cfg="$(store_config "$1")"
  n="$(awk '/^orchestration:/{f=1;next} f && /^[a-zA-Z]/{exit} f && /^[[:space:]]+gate_timeout:/{print $2; exit}' "$cfg" 2>/dev/null || true)"
  echo "${n:-1800}"
}

# run_gate <store-slug> <shell-code>: a gate that waits on stdin or a server
# that never exits would otherwise hang the loop with no signal. The code runs
# in its own process group so the TERM/KILL reaches npm, vite and browsers it
# spawned, not just the shell; perl because macOS ships no `timeout`.
run_gate() {
  local secs; secs="$(gate_timeout "$1")"
  local status=0
  perl -e '
    my $t = shift; my $pid = fork;
    if (!$pid) { setpgrp(0, 0); exec @ARGV or exit 127 }
    $SIG{ALRM} = sub { kill "TERM", -$pid; sleep 5; kill "KILL", -$pid; waitpid($pid, 0); exit 124 };
    alarm $t; waitpid($pid, 0);
    exit($? & 127 ? 128 + ($? & 127) : $? >> 8);
  ' "$secs" bash -c "$2" </dev/null || status=$?
  [ "$status" -ne 124 ] || echo "gate timed out after ${secs}s (orchestration.gate_timeout)" >&2
  return "$status"
}

# model_for_tier <store-slug> <tier> -> model id for mechanical|standard|deep|max
# (the `none` tier runs no model — it's plain bash bookkeeping). Reads
# orchestration.model_<tier> from the store's config first; falls back to
# the default table below when unset. The default table is the only place
# in the engine that names a specific model id — update it here, not
# per-callsite, when the current-best model changes.
model_for_tier() {
  local slug="$1" tier="$2"
  local cfg
  cfg="$(store_config "$slug")"
  local key="model_${tier}"
  local v
  v="$(awk -v key="$key" '
    /^orchestration:/ { f=1; next }
    f && /^[a-zA-Z]/ { exit }
    f && index($0, key":") { sub(".*"key":[ ]*", ""); gsub(/^"|"$/, ""); print; exit }
  ' "$cfg" 2>/dev/null || true)"
  if [ -n "$v" ]; then
    echo "$v"
    return 0
  fi
  case "$tier" in
    mechanical) echo "claude-haiku-4-5-20251001" ;;
    standard)   echo "claude-sonnet-5" ;;
    deep)       echo "claude-opus-5" ;;
    max)        echo "claude-fable-5-1" ;;
    *)          echo "unknown tier: $tier" >&2; return 1 ;;
  esac
}

# orch_scalar <store-slug> <key> -> orchestration.<key> as a bare scalar,
# empty if unset. Same single-line awk-over-config convention as above.
orch_scalar() {
  local cfg; cfg="$(store_config "$1")"
  awk -v key="$2" '
    /^orchestration:/ { f=1; next }
    f && /^[a-zA-Z]/ { exit }
    f && index($0, key":") { sub(".*"key":[ ]*", ""); gsub(/^"|"$/, ""); print; exit }
  ' "$cfg" 2>/dev/null || true
}

# checker_effort <store-slug> -> orchestration.checker_effort, empty if
# unset. When set, a checker may share the generator's model: the different
# configuration (this effort, plus the fresh context and the input contract
# every checker already gets) is what separates the two reads.
checker_effort() { orch_scalar "$1" checker_effort; }

# Role overlays: project-specific notes a store appends to one of the
# engine's role prompts, kept beside config.yaml so they version with the
# specs and never touch the target project. Fixed role set, so a typo is an
# error rather than a silently ignored file.
ROLES="proposer critic worker unit-critic verifier"

# role_overlay <store-slug> <role> -> path of <store>/openspec/roles/<role>.md
# if it exists, empty otherwise. Exits non-zero on an unknown role.
role_overlay() {
  case " $ROLES " in *" $2 "*) ;; *) echo "unknown role '$2' (expected one of: $ROLES)" >&2; return 1 ;; esac
  local f; f="$(store_path "$1")/openspec/roles/$2.md"
  [ -f "$f" ] && echo "$f"
  return 0
}

# Resolved at source time, from lib.sh's own location, so the path holds
# whatever the caller's cwd is when role_prompt runs.
ENGINE_ROLES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/roles"

# role_prompt <role> -> path of the engine's scripts/roles/<role>.md. A
# missing file is an incomplete engine checkout, so it errors rather than
# letting `next` silently omit the prompt.
role_prompt() {
  case " $ROLES " in *" $1 "*) ;; *) echo "unknown role '$1' (expected one of: $ROLES)" >&2; return 1 ;; esac
  local f="$ENGINE_ROLES_DIR/$1.md"
  [ -f "$f" ] || { echo "engine role prompt missing: $f" >&2; return 1; }
  echo "$f"
}

# role_for_action <action> -> the role whose overlay a `next` action
# dispatches with, empty for none-tier actions.
role_for_action() {
  case "$1" in
    classify|propose|revise) echo proposer ;;
    critique) echo critic ;;
    unit-spawn|unit-revise|fix|sweep|merge-conflict|split) echo worker ;;
    unit-critique) echo unit-critic ;;
    verify) echo verifier ;;
  esac
}

# stage_skills <store-slug> <stage> -> newline-separated project-skill names
# mapped to that stage's orchestration.stage_skills entry, empty if unset.
# `plan` is a bare scalar (`plan: project-spec-drafter`); `critic`/`test` are
# a flow-style list (`critic: [project-code-review, other-skill]`) — this
# only parses that one-line flow form, not YAML's multi-line block-list
# style, matching the rest of this file's single-line awk-over-config
# convention. See docs/proposals/skill-stage-mapping.md for the full design:
# `plan`, if set, REPLACES the deep-tier drafter; `critic`/`test`, if
# non-empty, STACK on top of the built-in tier/model checker — the caller
# (never this function) is responsible for honoring that distinction and
# for actually dispatching each name via the Skill tool.
stage_skills() {
  local slug="$1" stage="$2"
  local cfg
  cfg="$(store_config "$slug")"
  [ -f "$cfg" ] || return 0
  awk -v key="$stage" '
    /^orchestration:/ { f=1; next }
    f && /^[a-zA-Z]/ { exit }
    f && /^  stage_skills:/ { g=1; next }
    g && /^  [a-zA-Z]/ { exit }
    g && $0 ~ "^    "key":" {
      line = $0
      sub("^    "key":[ ]*", "", line)
      gsub(/^\[/, "", line); gsub(/\]$/, "", line)
      gsub(/, */, "\n", line)
      gsub(/^"|"$/, "", line)
      n = split(line, parts, "\n")
      for (i = 1; i <= n; i++) {
        v = parts[i]
        gsub(/^ +| +$/, "", v)
        gsub(/^"|"$/, "", v)
        if (v != "") print v
      }
      exit
    }
  ' "$cfg" 2>/dev/null || true
}

timestamp() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# State module: sole owner of the state-file YAML dialect (flat "key: value",
# values may contain colons, optional surrounding quotes). Nothing outside
# these three functions may awk/grep a state file.
state_root() {
  echo "$(orchestration_dir "$1")/state"
}

# workspace_path <store-slug> <change-name> [<unit>] — where a change's (or
# a unit's) worktree is checked out. Under the store, not the project: the
# project's repo owns the branch and history (git records the worktree in
# its .git/worktrees), but its main checkout must never see orchestration
# files. The store is a git repo too, so ensure_workspace_ignored keeps the
# checkout out of it. The sole builder of workspace paths — a unit path is
# always `<name>.<unit>` under the same workspaces/ dir, never built
# ad hoc elsewhere.
workspace_path() {
  local slug="$1" name="$2" unit="${3:-}"
  if [ -n "$unit" ]; then
    echo "$(orchestration_dir "$slug")/workspaces/$name.$unit"
  else
    echo "$(orchestration_dir "$slug")/workspaces/$name"
  fi
}

# unit_branch <change-name> <unit> -> change/<name>.<unit>. Not
# change/<name>/<unit> — git stores change/<name> as a ref file, so a
# sibling path under it would conflict with that file while the change
# branch exists.
unit_branch() {
  echo "change/$1.$2"
}

# unit_rebase_in_progress <unit-worktree> -- true when a rebase-merge or
# rebase-apply dir exists for that worktree. `git rev-parse --git-path`
# prints a path relative to the worktree for the main checkout but an
# absolute path for a linked worktree (its rebase state lives under the
# main repo's .git/worktrees/<name>/), so both forms are handled here.
unit_rebase_in_progress() {
  local wt="$1" p state
  for state in rebase-merge rebase-apply; do
    p="$(git -C "$wt" rev-parse --git-path "$state" 2>/dev/null)" || continue
    case "$p" in /*) ;; *) p="$wt/$p" ;; esac
    [ -d "$p" ] && return 0
  done
  return 1
}

# unit_state_dir <store-slug> <change-name> -> directory of per-unit state
# files (<state>/<name>.units/<unit>.yaml). Globbed as *.yaml only within
# this directory, so cmd_status's top-level *.yaml glob never picks these up.
unit_state_dir() {
  echo "$(state_root "$1")/$2.units"
}

# unit_capacity <store-slug> -> orchestration.unit_concurrency, else
# orchestration.concurrency, else 1. A unit is a different resource than a
# change, so it gets its own key, defaulting to the change-level one so an
# unconfigured store behaves as before this feature existed.
unit_capacity() {
  local slug="$1"
  local cfg; cfg="$(store_config "$slug")"
  local n
  n="$(awk '/^orchestration:/{f=1;next} f && /^[a-zA-Z]/{exit} f && /unit_concurrency:/{print $2; exit}' "$cfg" 2>/dev/null || true)"
  echo "${n:-3}"
}

# parallel_mode <store-slug> <state-file> -> true|false. Empty state field
# reads the store's orchestration.parallel; empty there reads true; any
# other value is a caller error (next_action exits non-zero).
parallel_mode() {
  local slug="$1" file="$2"
  local v; v="$(state_field "$file" parallel)"
  if [ -z "$v" ]; then
    local cfg; cfg="$(store_config "$slug")"
    v="$(awk '/^orchestration:/{f=1;next} f && /^[a-zA-Z]/{exit} f && /^[[:space:]]+parallel:/{print $2; exit}' "$cfg" 2>/dev/null || true)"
  fi
  v="${v:-true}"
  case "$v" in
    true|false) echo "$v" ;;
    *) echo "unknown parallel '$v' (expected true|false)" >&2; return 1 ;;
  esac
}

UNIT_ITER_CAP=5
# Consecutive red iterations after which `unit iterate` refuses to run
# again until the advisor has been asked for the unit. Measured: a worker
# that is red twice on the same check does not fix it alone on the third
# try; it fixes it on the fifth, or never.
REDS_BEFORE_ADVISOR=2

# --- map dialect: "<k>=<a>,<b>;<k>=<c>" shared by seams/units/unit_deps/
# unit_tasks. Nothing outside these two functions parses that dialect.
map_keys() {
  local value="$1"
  [ -n "$value" ] || return 0
  local old_ifs="$IFS" out=""
  IFS=';'
  local pair
  for pair in $value; do
    [ -n "$pair" ] || continue
    out="$out${pair%%=*} "
  done
  IFS="$old_ifs"
  printf '%s\n' "${out% }"
}

map_get() {
  local value="$1" key="$2"
  [ -n "$value" ] || return 0
  local old_ifs="$IFS"
  IFS=';'
  local pair
  for pair in $value; do
    [ -n "$pair" ] || continue
    if [ "${pair%%=*}" = "$key" ]; then
      IFS="$old_ifs"
      echo "${pair#*=}"
      return 0
    fi
  done
  IFS="$old_ifs"
  return 0
}

UNIT_NAME_RE='^[a-z0-9]+(-[a-z0-9]+)*$'

# Unit size caps: a unit is a tiny testable piece, not a file-ownership
# bucket. Measured: the units that ran 229 and 349 turns owned 13-14
# files each; the ones that went green first time owned 3-6.
UNIT_MAX_FILES=8
UNIT_MAX_TASKS=3
unit_max_files() { local v; v="$(orch_scalar "$1" unit_max_files)"; echo "${v:-$UNIT_MAX_FILES}"; }
unit_max_tasks() { local v; v="$(orch_scalar "$1" unit_max_tasks)"; echo "${v:-$UNIT_MAX_TASKS}"; }
count_csv() { printf '%s' "$1" | tr ',' '\n' | grep -c . || true; }

# units_check <store-slug> <name> -- state-only: reads the change's units,
# unit_deps, unit_tasks, seams fields and nothing else (no tasks.md, no
# worktree). Replaces an LLM critique of the split with mechanical
# properties: kebab names, every dep a known unit, deps acyclic, every unit
# file in some seams list, two units with overlapping files ordered by a
# dep path, every unit has >=1 file, a task id in at most one unit.
units_check() {
  local slug="$1" name="$2"
  local f="$(state_root "$slug")/$name.yaml"
  [ -f "$f" ] || { echo "no state for change $name in store $slug" >&2; return 1; }
  local units_v unit_deps_v unit_tasks_v seams_v
  units_v="$(state_field "$f" units)"
  unit_deps_v="$(state_field "$f" unit_deps)"
  unit_tasks_v="$(state_field "$f" unit_tasks)"
  seams_v="$(state_field "$f" seams)"

  local units_list; units_list="$(map_keys "$units_v")"
  [ -n "$units_list" ] || { echo "units check: no units recorded" >&2; return 1; }

  local u
  for u in $units_list; do
    if ! [[ "$u" =~ $UNIT_NAME_RE ]]; then
      echo "units check: bad unit name '$u' (expected kebab-case)" >&2
      return 1
    fi
    local files; files="$(map_get "$units_v" "$u")"
    [ -n "$files" ] || { echo "units check: unit '$u' has no files" >&2; return 1; }
  done

  # size caps: over the cap is an error unless the unit is named in
  # unit_size_ok (a justification the proposal must carry), then a warning
  local maxf maxt okv; maxf="$(unit_max_files "$slug")"; maxt="$(unit_max_tasks "$slug")"
  okv="$(state_field "$f" unit_size_ok)"
  for u in $units_list; do
    local nf nt; nf="$(count_csv "$(map_get "$units_v" "$u")")"; nt="$(count_csv "$(map_get "$unit_tasks_v" "$u")")"
    [ "$nf" -gt "$maxf" ] || [ "$nt" -gt "$maxt" ] || continue
    case ",$okv," in
      *",$u,"*) echo "units check: unit '$u' is over the size cap ($nf files, $nt tasks; cap $maxf/$maxt) — allowed by unit_size_ok" >&2 ;;
      *) echo "units check: unit '$u' is over the size cap ($nf files, $nt tasks; cap $maxf files / $maxt tasks): split it into smaller units, or justify it in the proposal and record state set unit_size_ok $u" >&2; return 1 ;;
    esac
  done

  # seam files: union of every seams group's file list
  local seam_files=","
  local sk
  for sk in $(map_keys "$seams_v"); do
    local sf; sf="$(map_get "$seams_v" "$sk")"
    local old_ifs="$IFS"; IFS=','
    local one
    for one in $sf; do
      [ -n "$one" ] || continue
      seam_files="$seam_files$one,"
    done
    IFS="$old_ifs"
  done
  for u in $units_list; do
    local files; files="$(map_get "$units_v" "$u")"
    local old_ifs="$IFS"; IFS=','
    local one
    for one in $files; do
      [ -n "$one" ] || continue
      case "$seam_files" in
        *",$one,"*) ;;
        *) echo "units check: file '$one' (unit '$u') is not in any seams list" >&2; return 1 ;;
      esac
    done
    IFS="$old_ifs"
  done

  # deps: known units only
  local dep_keys; dep_keys="$(map_keys "$unit_deps_v")"
  for u in $dep_keys; do
    case " $units_list " in *" $u "*) ;; *) echo "units check: unit_deps names unknown unit '$u'" >&2; return 1 ;; esac
    local deps; deps="$(map_get "$unit_deps_v" "$u" | tr ',' ' ')"
    local d
    for d in $deps; do
      [ -n "$d" ] || continue
      case " $units_list " in *" $d "*) ;; *) echo "units check: unit '$u' depends on unknown unit '$d'" >&2; return 1 ;; esac
    done
  done

  # acyclic: DFS with a visiting/visited mark kept in space-delimited lists
  local visiting=" " visited=" "
  _units_check_visit() {
    local node="$1"
    case "$visiting" in
      *" $node "*)
        # report the cycle path from the re-entered node onward, so every
        # node on the cycle is named, not just the one that closed it
        local path; path="$(echo "$visiting" | sed -e "s/^ *//" -e "s/ *$//")"
        local cycle="" seen_start=""
        local n
        for n in $path; do
          if [ "$n" = "$node" ]; then seen_start=1; fi
          [ -n "$seen_start" ] && cycle="$cycle$n "
        done
        echo "units check: cycle in unit_deps: ${cycle}${node}" >&2
        return 1
        ;;
    esac
    case "$visited" in *" $node "*) return 0 ;; esac
    visiting="$visiting$node "
    local d
    for d in $(map_get "$unit_deps_v" "$node" | tr ',' ' '); do
      [ -n "$d" ] || continue
      _units_check_visit "$d" || return 1
    done
    visiting="${visiting/ $node / }"
    visited="$visited$node "
    return 0
  }
  for u in $units_list; do
    _units_check_visit "$u" || return 1
  done

  # dep-reachability, for the overlap check below
  _units_depends_on() { # <a> <b> -> 0 if a depends on b, directly or transitively
    local a="$1" b="$2" seen=" "
    _udo() {
      local n="$1"
      case "$seen" in *" $n "*) return 1 ;; esac
      seen="$seen$n "
      local d
      for d in $(map_get "$unit_deps_v" "$n" | tr ',' ' '); do
        [ -n "$d" ] || continue
        [ "$d" = "$b" ] && return 0
        _udo "$d" && return 0
      done
      return 1
    }
    _udo "$a"
  }

  # overlap: two units sharing a file must be ordered by a dep path
  local ulist=($units_list)
  local i j
  for ((i = 0; i < ${#ulist[@]}; i++)); do
    for ((j = i + 1; j < ${#ulist[@]}; j++)); do
      local ua="${ulist[$i]}" ub="${ulist[$j]}"
      local fa; fa="$(map_get "$units_v" "$ua")"
      local overlap=""
      local old_ifs="$IFS"; IFS=','
      local one
      for one in $fa; do
        [ -n "$one" ] || continue
        case ",$(map_get "$units_v" "$ub")," in *",$one,"*) overlap="$one"; break ;; esac
      done
      IFS="$old_ifs"
      if [ -n "$overlap" ]; then
        if ! _units_depends_on "$ua" "$ub" && ! _units_depends_on "$ub" "$ua"; then
          echo "units check: '$ua' and '$ub' both list '$overlap' with no dep path between them" >&2
          return 1
        fi
      fi
    done
  done

  # task ids: each in at most one unit
  local seen_tasks=","
  for u in $units_list; do
    local tasks; tasks="$(map_get "$unit_tasks_v" "$u")"
    local old_ifs="$IFS"; IFS=','
    local t
    for t in $tasks; do
      [ -n "$t" ] || continue
      case "$seen_tasks" in
        *",$t,"*) echo "units check: task '$t' is assigned to more than one unit" >&2; return 1 ;;
      esac
      seen_tasks="$seen_tasks$t,"
    done
    IFS="$old_ifs"
  done
  return 0
}

# units_ready <store-slug> <name> -- prints "ready: <u> ...", "running: <u>
# ...", "capacity: <n>". A slot holder is a unit whose state file has
# status running|reviewing|conflict|resolving. Ready units are
# those with no state file or `status: pending` whose deps are all merged, in `units`
# field order, capped at the free capacity.
units_ready() {
  local slug="$1" name="$2"
  local f="$(state_root "$slug")/$name.yaml"
  local units_v unit_deps_v
  units_v="$(state_field "$f" units)"
  unit_deps_v="$(state_field "$f" unit_deps)"
  local udir; udir="$(unit_state_dir "$slug" "$name")"
  local cap; cap="$(unit_capacity "$slug")"

  status_of() {
    local uf="$udir/$1.yaml"
    [ -f "$uf" ] && state_field "$uf" status || echo pending
  }
  local running="" u
  for u in $(map_keys "$units_v"); do
    local st; st="$(status_of "$u")"
    case "$st" in running|reviewing|conflict|resolving) running="$running$u " ;; esac
  done
  local holders; holders="$(echo "$running" | tr -s ' ' '\n' | grep -c . || true)"
  local free=$((cap - holders))
  [ "$free" -ge 0 ] || free=0

  local ready="" count=0
  for u in $(map_keys "$units_v"); do
    [ "$count" -lt "$free" ] || break
    local st; st="$(status_of "$u")"
    [ "$st" = pending ] || continue
    local ok=1 d
    for d in $(map_get "$unit_deps_v" "$u" | tr ',' ' '); do
      [ -n "$d" ] || continue
      [ "$(status_of "$d")" = merged ] || { ok=0; break; }
    done
    [ "$ok" = 1 ] || continue
    ready="$ready$u "
    count=$((count + 1))
  done

  printf 'ready: %s\n' "${ready% }"
  printf 'running: %s\n' "${running% }"
  printf 'capacity: %s\n' "$free"
}

# units_merge_order <store-slug> <name> -- Kahn's algorithm over unit_deps,
# ties broken by `units` field order; exits non-zero naming the units left
# on a cycle.
units_merge_order() {
  local slug="$1" name="$2"
  local f="$(state_root "$slug")/$name.yaml"
  local units_v unit_deps_v
  units_v="$(state_field "$f" units)"
  unit_deps_v="$(state_field "$f" unit_deps)"
  local order=() remaining=($(map_keys "$units_v"))
  while [ "${#remaining[@]}" -gt 0 ]; do
    local progressed=0
    local next_remaining=()
    local u
    for u in "${remaining[@]}"; do
      local ok=1 d
      for d in $(map_get "$unit_deps_v" "$u" | tr ',' ' '); do
        [ -n "$d" ] || continue
        case " ${order[*]:-} " in *" $d "*) ;; *) ok=0 ;; esac
      done
      if [ "$ok" = 1 ]; then
        order+=("$u")
        progressed=1
      else
        next_remaining+=("$u")
      fi
    done
    remaining=(${next_remaining[@]+"${next_remaining[@]}"})
    if [ "$progressed" = 0 ]; then
      echo "units merge-order: cycle involving ${remaining[*]}" >&2
      return 1
    fi
  done
  echo "${order[*]}"
}

ensure_workspace_ignored() {
  local store; store="$(store_path "$1")"
  local ignore="$store/.gitignore"
  grep -qxF '.orchestration/workspaces/' "$ignore" 2>/dev/null && return 0
  echo '.orchestration/workspaces/' >> "$ignore"
}

# initiative_root <store-slug> — initiative records share the state-file YAML
# dialect (state_field/state_write) but live apart from change state so
# `status` never mistakes one for a change.
initiative_root() {
  echo "$(orchestration_dir "$1")/initiatives"
}

# state_field <file> <key> -> value with surrounding quotes stripped, empty if absent.
state_field() {
  awk -v k="$2" '
    index($0, k": ") == 1 {
      v = substr($0, length(k) + 3)
      gsub(/^"|"$/, "", v)
      print v; exit
    }
    $0 == k":" { print ""; exit }
  ' "$1"
}

# state_write <file> key value [key value ...] — upsert pairs, refresh updated_at.
state_write() {
  local f="$1"; shift
  while [ $# -ge 2 ]; do
    local key="$1" val="$2"; shift 2
    local tmp="$f.tmp"
    if grep -q "^$key:" "$f"; then
      awk -v k="$key" -v v="$val" '
        index($0, k":") == 1 { print k": "v; next } { print }
      ' "$f" > "$tmp"
    else
      cat "$f" > "$tmp"
      echo "$key: $val" >> "$tmp"
    fi
    mv "$tmp" "$f"
  done
  awk -v v="$(timestamp)" '
    index($0, "updated_at:") == 1 { print "updated_at: \""v"\""; next } { print }
  ' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
}

# Session log: sole owner of the session-history file, one logfmt line per
# orchestrator/worker run against a change (name=value pairs, space
# separated, values must not contain spaces). Append-only — a run's entry
# is never edited after the fact, only added to. Nothing outside these four
# functions may write or parse a session log.
session_log_path() {
  echo "$(state_root "$1")/$2.sessions.log"
}

# session_append <file> key value [key value ...] — append one line, ts auto-set.
session_append() {
  local f="$1"; shift
  mkdir -p "$(dirname "$f")"
  local line="ts=$(timestamp)"
  while [ $# -ge 2 ]; do
    line="$line $1=$2"
    shift 2
  done
  echo "$line" >> "$f"
}

# last_session_field <store-slug> <change-name> <phase-regex> <field> -> that
# field of the most recent session entry whose phase matches, empty if none.
# The session log is the only record of who wrote what, and at which tier.
last_session_field() {
  local f; f="$(session_log_path "$1" "$2")"
  [ -f "$f" ] || return 0
  grep -E "phase=($3)" "$f" 2>/dev/null | tail -n1 \
    | grep -o "$4=[^ ]*" | cut -d= -f2 || true
}

# advisor_calls <store-slug> <change-name> -> count of role=advisor session
# entries. The per-change advisor cap (see Advisor in
# AUTONOMOUS-ORCHESTRATION.md) is enforced by the orchestrator against this
# number; the log is the only record of it, so nothing else caches a count.
ADVISOR_CAP=2
advisor_calls() {
  local f; f="$(session_log_path "$1" "$2")"
  [ -f "$f" ] || { echo 0; return 0; }
  grep -c 'role=advisor' "$f" || true
}

# advisor_calls_for <store-slug> <change-name> <worker-transcript-id> -> how
# many advisor entries already name this worker (`for=<id>`). Per-worker cap
# is 1: a second question means the task isn't routine — escalate the task.
advisor_calls_for() {
  local f; f="$(session_log_path "$1" "$2")"
  [ -f "$f" ] || { echo 0; return 0; }
  grep 'role=advisor' "$f" | grep -c "for=$3\( \|$\)" || true
}

# The implementer is whoever last wrote code (applying/checking entries);
# the proposer is whoever drafted the current delta spec (proposed entries).
implementer_model() { last_session_field "$1" "$2" 'applying|checking' model; }
implementer_tier()  { last_session_field "$1" "$2" 'applying|checking' tier; }
proposer_model()    { last_session_field "$1" "$2" 'proposed' model; }
proposer_tier()     { last_session_field "$1" "$2" 'proposed' tier; }

# Tier ladder, weakest first. checker_pick walks it; nothing else orders tiers.
TIERS="mechanical standard deep max"

# tier_of_model <store-slug> <model> -> the tier that resolves to this model,
# empty if none does. Only for session entries written without a tier.
tier_of_model() {
  local t
  for t in $TIERS; do
    [ "$(model_for_tier "$1" "$t")" = "$2" ] && { echo "$t"; return 0; }
  done
  return 0
}

# checker_pick <store-slug> <gen-tier> <gen-model> <label> -> "<tier> <model>"
# for the generator/checker split. The checker is the tier one ABOVE the
# generator's: the review is done by a stronger model than the one whose
# work it grades. Only when the generator already sits at the top tier,
# where no stronger one exists, does the tier one BELOW review instead.
# Either way the checker's model must differ from the generator's — a model
# is a weak reviewer of its own output — so a store whose config maps that
# neighbouring tier onto the generator's model is an error, never a silent
# same-model review or a quiet drop to a weaker tier.
checker_pick() {
  local slug="$1" gtier="$2" gen="$3" label="$4"
  if [ -z "$gtier" ] && [ -n "$gen" ]; then gtier="$(tier_of_model "$slug" "$gen")"; fi
  [ -n "$gtier" ] || { echo "cannot tell which tier $label ($gen) ran at — session entries must record tier" >&2; return 1; }
  local ladder=($TIERS) i idx=-1
  for i in "${!ladder[@]}"; do [ "${ladder[$i]}" = "$gtier" ] && idx=$i; done
  [ "$idx" -ge 0 ] || { echo "unknown tier '$gtier' for $label" >&2; return 1; }
  local cand=$((idx + 1)); [ "$cand" -lt "${#ladder[@]}" ] || cand=$((idx - 1))
  local t="${ladder[$cand]}" m; m="$(model_for_tier "$slug" "$t")"
  [ "$m" != "$gen" ] && { echo "$t $m"; return 0; }
  [ -n "$(checker_effort "$slug")" ] && { echo "$t $m"; return 0; }
  echo "checker tier $t resolves to the $label's own model ($gen) — map a different model in orchestration.model_* or set orchestration.checker_effort in $(store_config "$slug")" >&2
  return 1
}

# unit_tier <store-slug> <name> <unit> -> deep for a foundation unit — one
# with two or more direct dependents: its defects cost every dependent a
# rerun and it serialises the wave. A link in a chain (one dependent) is
# standard: measured, a chained split made 7 of 8 units "foundation" and
# routed each to deep plus a max critic for no fan-out at all.
FOUNDATION_MIN_DEPENDENTS=2
unit_tier() {
  local deps_v; deps_v="$(state_field "$(state_root "$1")/$2.yaml" unit_deps)"
  local k n=0
  for k in $(map_keys "$deps_v"); do
    [ "$k" = "$3" ] && continue
    case ",$(map_get "$deps_v" "$k")," in *",$3,"*) n=$((n + 1)) ;; esac
  done
  [ "$n" -ge "$FOUNDATION_MIN_DEPENDENTS" ] && echo deep || echo standard
}

# unit_logged_tier <store-slug> <name> <unit> -> the tier recorded on the
# unit's state file at `unit create`, else unit_tier (a unit file written
# before tiers were recorded).
unit_logged_tier() {
  local uf; uf="$(unit_state_dir "$1" "$2")/$3.yaml"
  local t=""; [ -f "$uf" ] && t="$(state_field "$uf" tier)"
  [ -n "$t" ] && echo "$t" || unit_tier "$1" "$2" "$3"
}

# unit_pass_eligible <store-slug> <name> <unit> -> 0 when the unit may be
# merged without a unit critic: lifecycle light, not a UI unit, a standard
# leaf, green on its first iteration, no critique recorded. Measured: unit
# critics over such leaves found nothing, and Verify still reads the whole
# merged diff. Prints the failing condition on stderr otherwise.
unit_pass_eligible() {
  local slug="$1" name="$2" u="$3"
  local f="$(state_root "$slug")/$name.yaml"
  local uf; uf="$(unit_state_dir "$slug" "$name")/$u.yaml"
  [ -f "$uf" ] || { echo "no unit $u for change $name" >&2; return 1; }
  local lc; lc="$(state_field "$f" lifecycle)"; lc="${lc:-full}"
  [ "$lc" = light ] || { echo "unit $u: lifecycle is $lc, only light may skip the unit critic" >&2; return 1; }
  case ",$(state_field "$f" ui_units)," in *",$u,"*) echo "unit $u is a UI unit: its screenshot needs a critic" >&2; return 1 ;; esac
  [ "$(unit_logged_tier "$slug" "$name" "$u")" = standard ] || { echo "unit $u is a foundation unit (deep): keeps its critic" >&2; return 1; }
  [ "$(state_field "$uf" status)" = green ] || { echo "unit $u is not green (status: $(state_field "$uf" status))" >&2; return 1; }
  [ "$(state_field "$uf" iterations)" = 1 ] || { echo "unit $u took $(state_field "$uf" iterations) iterations, not 1" >&2; return 1; }
  [ -z "$(state_field "$uf" critique)" ] || { echo "unit $u already has a critique" >&2; return 1; }
  return 0
}

# unit_critic_pick <store-slug> <name> <unit> -> "<tier> <model>": the unit
# critic is sized against the unit's own worker, not the proposer.
unit_critic_pick() {
  local t; t="$(unit_logged_tier "$1" "$2" "$3")"
  checker_pick "$1" "$t" "$(model_for_tier "$1" "$t")" "unit $3 worker"
}

# With no session history at all the generator is assumed at its nominal
# tier: implementers at standard, proposers at deep (Propose always runs
# there). An entry with a model but no tier is inferred, not defaulted.
# Verify's floor: never below deep, and never below the previous Verify
# round on this change. The tier-above rule sizes the checker to the last
# fixer; after a mechanical fix that put the final sign-off on a standard
# model (measured), and a round that closes a stronger round's findings
# cannot be read by a weaker model.
VERIFY_FLOOR=deep
tier_index() { local i=0 t; for t in $TIERS; do [ "$t" = "$1" ] && { echo "$i"; return 0; }; i=$((i + 1)); done; echo -1; }
verify_pick() {
  local t m; t="$(implementer_tier "$1" "$2")"; m="$(implementer_model "$1" "$2")"
  [ -n "$t$m" ] || t=standard
  local pick; pick="$(checker_pick "$1" "$t" "$m" implementer)" || return 1
  local above="${pick%% *}" prev; prev="$(last_session_field "$1" "$2" verify tier)"
  local chosen="$above" note=""
  if [ "$(tier_index "$VERIFY_FLOOR")" -gt "$(tier_index "$chosen")" ]; then chosen="$VERIFY_FLOOR"; note="floor: $VERIFY_FLOOR"; fi
  if [ -n "$prev" ] && [ "$(tier_index "$prev")" -gt "$(tier_index "$chosen")" ]; then chosen="$prev"; note="floor: previous round ran at $prev"; fi
  local model; model="$(model_for_tier "$1" "$chosen")"
  if [ "$model" = "$m" ] && [ -z "$(checker_effort "$1")" ]; then
    echo "verify floor tier $chosen resolves to the implementer's own model ($m) — check orchestration.model_* in $(store_config "$1")" >&2; return 1
  fi
  echo "$chosen $model${note:+ $note}"
}
verify_note() { verify_pick "$1" "$2" 2>/dev/null | cut -d' ' -f3-; }
critic_pick() {
  local t m; t="$(proposer_tier "$1" "$2")"; m="$(proposer_model "$1" "$2")"
  [ -n "$t$m" ] || t=deep
  checker_pick "$1" "$t" "$m" proposer
}
verify_model() { verify_pick "$1" "$2" | cut -d' ' -f2; }
verify_tier()  { verify_pick "$1" "$2" | cut -d' ' -f1; }
critic_model() { critic_pick "$1" "$2" | cut -d' ' -f2; }
critic_tier()  { critic_pick "$1" "$2" | cut -d' ' -f1; }

# --- next_action: the orchestration policy as one function -----------------
# next_action <store-slug> <change-name> prints the single next step for a
# change, derived only from its state file and session log — never from
# chat memory. Output is key: value lines:
#   action    what to do (see the doc's lifecycle; gate0/gate1/gate2/
#             gate2-manual = ask human — gate0 always fires, once per
#             proposal round, before Apply; gate1/gate2/gate2-manual only
#             on trouble, an open manual task, or before merge; tasks-open
#             means run `tasks open` to record manual_tasks_open — archive
#             only ever fires from phase verified)
#   tier      effort tier for the step, or none
#   model     resolved model id, or - for none-tier steps
#   set_phase phase to record once the step completes (absent = unchanged)
#   reason    the rule that produced this answer
#   also      a second, read-only step to dispatch concurrently (only on
#   also_model  `check`: Verify, with its tier-above model id)
#   also_prompt (`check` only) the engine prompt path for that Verify
#   prompt    the engine prompt path for the action's role (role-bearing
#             actions only), printed before any overlay line
#   running   (phase=applying only, every output but split) the unit slot
#             holders at this moment, possibly empty
#   units     (phase=applying only, where the action names units) the
#             units the action applies to
# Every threshold here mirrors a rule in AUTONOMOUS-ORCHESTRATION.md; if
# they ever disagree, the doc is wrong and this is right, because this is
# what runs. Read-only: the orchestrator does the step and records results.
FIX_CAP=3
PROPOSE_CAP=2

# Pillar readings, recorded by the classify step as
# `scope=<v>;blast=<v>;novelty=<v>;deps=<v>`. Each value list is ordered
# lowest first; the first entry of each is the trivial reading.
PILLAR_SCOPE="file seam seams"
PILLAR_BLAST="none project public"
PILLAR_NOVELTY="known new"
PILLAR_DEPS="none dev runtime"

# pillars_check <pillars> -> 0 when every key is present with a known
# value; prints the first problem on stderr otherwise.
pillars_check() {
  local p="$1" k v allowed
  for k in scope blast novelty deps; do
    v="$(map_get "$p" "$k")"
    case "$k" in scope) allowed="$PILLAR_SCOPE" ;; blast) allowed="$PILLAR_BLAST" ;; novelty) allowed="$PILLAR_NOVELTY" ;; deps) allowed="$PILLAR_DEPS" ;; esac
    [ -n "$v" ] || { echo "pillars: missing '$k' (expected scope=..;blast=..;novelty=..;deps=..)" >&2; return 1; }
    case " $allowed " in *" $v "*) ;; *) echo "pillars: unknown $k '$v' (expected one of: $allowed)" >&2; return 1 ;; esac
  done
}

# pillars_trivial <pillars> -> 0 when every pillar is at its lowest
# reading except scope, where one seam still counts as trivial (a
# localized fix usually touches one seam, not one file). Only such a
# change skips grill mode.
pillars_trivial() {
  local p="$1"
  case "$(map_get "$p" scope)" in file|seam) ;; *) return 1 ;; esac
  [ "$(map_get "$p" blast)" = none ] && [ "$(map_get "$p" novelty)" = known ] && [ "$(map_get "$p" deps)" = none ]
}

# emit_role_lines <slug> <action> -> for a role-bearing action prints
# `prompt: <path>`, then `overlay: <path>` when the store has an overlay
# for that role.
# role_agent <role> -> the Claude Code agent definition the orchestrator
# dispatches this role as (`subagent_type`), installed by Atlas beside the
# skill. It carries the role's effort and tool allowlist; the model still
# comes from the tier table, passed on the Agent call.
role_agent() { echo "openspec-$1"; }

emit_role_lines() {
  local r; r="$(role_for_action "$2")"
  [ -n "$r" ] || return 0
  local p; p="$(role_prompt "$r")" || return 1
  printf 'prompt: %s\n' "$p"
  local ov; ov="$(role_overlay "$1" "$r")"
  [ -n "$ov" ] && printf 'overlay: %s\n' "$ov"
  printf 'agent: %s\n' "$(role_agent "$r")"
  return 0
}

# next_action_applying <slug> <name> <state-file> <lifecycle> -- the
# phase=applying action table. Reads only state files (the change's and
# each unit's) and the session log, same as next_action overall. Every
# output other than split carries a running: line (slot holders, possibly
# empty) and, where it names units, a units: line.
next_action_applying() {
  local slug="$1" name="$2" f="$3" lc="$4"
  local units_v; units_v="$(state_field "$f" units)"

  _na_emit() { # action tier model reason [set_phase]
    printf 'action: %s\ntier: %s\nmodel: %s\n' "$1" "$2" "$3"
    [ -n "${5:-}" ] && printf 'set_phase: %s\n' "$5"
    printf 'reason: %s\n' "$4"
    emit_role_lines "$slug" "$1"
  }
  local ceffort; ceffort="$(checker_effort "$slug")"

  if [ -z "$units_v" ]; then
    local pmode; pmode="$(parallel_mode "$slug" "$f")" || return 1
    if [ "$lc" = full ] && [ "$pmode" = true ]; then
      _na_emit split deep "$(model_for_tier "$slug" deep)" "write units/unit_deps/unit_tasks/ui_units (seam dialect), then run units check"
    else
      _na_emit split none - "$lc lifecycle or parallel false: run units single (--ui if the change has UI) to make one unit 'all'"
    fi
    return 0
  fi

  units_check "$slug" "$name" || return 1

  local udir; udir="$(unit_state_dir "$slug" "$name")"
  local unit_list; unit_list="$(map_keys "$units_v")"
  local unit_deps_v; unit_deps_v="$(state_field "$f" unit_deps)"

  _na_status() {
    local uf="$udir/$1.yaml"
    [ -f "$uf" ] && state_field "$uf" status || echo pending
  }

  local ready_out; ready_out="$(units_ready "$slug" "$name")"
  local ready_line running_line
  ready_line="$(printf '%s\n' "$ready_out" | sed -n 's/^ready: //p')"
  running_line="$(printf '%s\n' "$ready_out" | sed -n 's/^running: //p')"

  local u

  # a unit failed -> gate1
  for u in $unit_list; do
    [ "$(_na_status "$u")" = failed ] || continue
    local why; why="$(state_field "$udir/$u.yaml" fail_reason)"
    case "$why" in
      spec) _na_emit gate1 none - "unit $u reports a check that contradicts the spec (fail_reason spec): the human owns the spec — show the worker's finding and the requirement it names; amend the spec (spec_amend accepted) or redraft" ;;
      red-after-advice) _na_emit gate1 none - "unit $u is still red after the advisor's answer (fail_reason red-after-advice): show the human the red iterate output, the advisor's answer, and the failing check" ;;
      iteration-cap) _na_emit gate1 none - "unit $u hit the iteration cap ($UNIT_ITER_CAP)" ;;
      merge-conflict) _na_emit gate1 none - "unit $u had an unrecoverable merge conflict" ;;
      *) _na_emit gate1 none - "unit $u failed (iteration cap reached, or an unrecoverable merge conflict)" ;;
    esac
    printf 'running: %s\n' "$running_line"
    return 0
  done

  # a unit is in conflict -> merge-conflict
  for u in $unit_list; do
    [ "$(_na_status "$u")" = conflict ] || continue
    _na_emit merge-conflict standard "$(model_for_tier "$slug" standard)" "unit $u has a rebase conflict: dispatch one agent confined to the conflicting files, then run unit merge again"
    printf 'units: %s\n' "$u"
    printf 'running: %s\n' "$running_line"
    return 0
  done

  # reviewing with a blocking critique -> unit-revise, or gate1 at the cap
  for u in $unit_list; do
    local uf="$udir/$u.yaml"
    [ -f "$uf" ] || continue
    [ "$(state_field "$uf" status)" = reviewing ] || continue
    local ucrit; ucrit="$(state_field "$uf" critique)"
    case "$ucrit" in
      blocking:*)
        local iters; iters="$(state_field "$uf" iterations)"; iters="${iters:-0}"
        if [ "$iters" -lt "$UNIT_ITER_CAP" ]; then
          local rt; rt="$(unit_logged_tier "$slug" "$name" "$u")"
          _na_emit unit-revise "$rt" "$(model_for_tier "$slug" "$rt")" "unit $u critique $ucrit, iteration $iters/$UNIT_ITER_CAP: set unit $u status running critique \"\" first, then resume or re-dispatch the worker with the report"
          printf 'units: %s\n' "$u"
        else
          _na_emit gate1 none - "unit $u critique still blocking at the iteration cap ($iters/$UNIT_ITER_CAP)"
        fi
        printf 'running: %s\n' "$running_line"
        return 0
        ;;
    esac
  done

  # reviewed units whose deps are all merged -> unit-merge, in merge order
  local mergeorder; mergeorder="$(units_merge_order "$slug" "$name")" || return 1
  local mergeable=""
  for u in $mergeorder; do
    local uf="$udir/$u.yaml"
    [ -f "$uf" ] || continue
    [ "$(state_field "$uf" status)" = reviewed ] || continue
    local depsok=1 d
    for d in $(map_get "$unit_deps_v" "$u" | tr ',' ' '); do
      [ -n "$d" ] || continue
      [ "$(_na_status "$d")" = merged ] || { depsok=0; break; }
    done
    [ "$depsok" = 1 ] && mergeable="$mergeable$u "
  done
  if [ -n "$mergeable" ]; then
    _na_emit unit-merge none - "reviewed units with every dep merged: fast-forward each onto change/$name in dependency order"
    printf 'units: %s\n' "${mergeable% }"
    printf 'running: %s\n' "$running_line"
    return 0
  fi

  # green with no critique yet -> unit-critique
  local green_units=""
  for u in $unit_list; do
    local uf="$udir/$u.yaml"
    [ -f "$uf" ] || continue
    [ "$(state_field "$uf" status)" = green ] || continue
    [ -z "$(state_field "$uf" critique)" ] || continue
    green_units="$green_units$u "
  done
  for u in $green_units; do
    unit_pass_eligible "$slug" "$name" "$u" 2>/dev/null || continue
    _na_emit unit-pass none - "light lifecycle: unit $u is a non-UI standard leaf green on iteration 1 — run unit pass (no critic; Verify still reads the merged diff), then unit merge"
    printf 'units: %s\n' "$u"
    printf 'running: %s\n' "$running_line"
    return 0
  done
  if [ -n "$green_units" ]; then
    # One dispatch per checker tier: a deep foundation unit and a standard
    # leaf green at the same time get different critics.
    local first; first="${green_units%% *}"
    local pick; pick="$(unit_critic_pick "$slug" "$name" "$first")" || return 1
    local ct="${pick%% *}" cm="${pick#* }" same=""
    for u in $green_units; do
      [ "$(unit_logged_tier "$slug" "$name" "$u")" = "$(unit_logged_tier "$slug" "$name" "$first")" ] && same="$same$u "
    done
    _na_emit unit-critique "$ct" "$cm" "green units with no critique yet: checker one tier above each unit's own worker ($(unit_logged_tier "$slug" "$name" "$first"))"
    [ -n "$ceffort" ] && printf 'effort: %s\n' "$ceffort"
    printf 'units: %s\n' "${same% }"
    printf 'running: %s\n' "$running_line"
    return 0
  fi

  # capacity free and a unit is ready -> unit-spawn
  if [ -n "$ready_line" ]; then
    local st=standard tiers=""
    for u in $ready_line; do
      local ut; ut="$(unit_tier "$slug" "$name" "$u")"
      tiers="$tiers$u=$ut;"; [ "$ut" = deep ] && st=deep
    done
    _na_emit unit-spawn "$st" "$(model_for_tier "$slug" "$st")" "capacity free: unit create then one Agent per ready unit, at the tier unit_tiers gives it (deep for a unit others depend on, standard for a leaf)"
    printf 'unit_tiers: %s\n' "${tiers%;}"
    printf 'units: %s\n' "$ready_line"
    printf 'running: %s\n' "$running_line"
    return 0
  fi

  # something is still in flight -> wait
  if [ -n "$running_line" ]; then
    _na_emit wait none - "a worker or critic is in flight: call next again when it returns"
    printf 'running: %s\n' "$running_line"
    return 0
  fi

  # every unit merged -> units-merged
  local all_merged=1
  for u in $unit_list; do
    [ "$(_na_status "$u")" = merged ] || { all_merged=0; break; }
  done
  if [ "$all_merged" = 1 ]; then
    _na_emit units-merged none - "every unit merged: rerun the full gate + Verify on the change branch" checking
    printf 'running: %s\n' "$running_line"
    return 0
  fi

  echo "units stalled for $name: no unit is ready, running, reviewed, green, or merged" >&2
  return 1
}

next_action() {
  local slug="$1" name="$2"
  local f="$(state_root "$slug")/$name.yaml"
  [ -f "$f" ] || { echo "no state for change $name in store $slug" >&2; return 1; }
  local phase crit pcrit prounds gate verify pverify fixes blocked accept
  local lifecycle lc ptier manual_open manual_accept
  phase="$(state_field "$f" phase)"
  crit="$(state_field "$f" last_critique_result)"
  pcrit="$(state_field "$f" prev_critique_result)"
  prounds="$(state_field "$f" propose_rounds)"; prounds="${prounds:-0}"
  gate="$(state_field "$f" last_gate_result)"
  verify="$(state_field "$f" last_verify_result)"
  pverify="$(state_field "$f" prev_verify_result)"
  fixes="$(state_field "$f" fix_attempts)"; fixes="${fixes:-0}"
  blocked="$(state_field "$f" blocked_on)"
  accept="$(state_field "$f" acceptance)"
  lifecycle="$(state_field "$f" lifecycle)"
  lc="${lifecycle:-full}"
  manual_open="$(state_field "$f" manual_tasks_open)"
  manual_accept="$(state_field "$f" manual_accept)"
  local spec_amend; spec_amend="$(state_field "$f" spec_amend)"
  local pillars grill; pillars="$(state_field "$f" pillars)"; grill="$(state_field "$f" grill)"
  local ceffort; ceffort="$(checker_effort "$slug")"
  case "$lc" in
    full) ptier=deep ;;
    light) ptier=standard ;;
    *) echo "unknown lifecycle '$lifecycle' (expected full|light)" >&2; return 1 ;;
  esac
  # Gate 0 always offers this escape hatch for a fast-path proposal; Propose
  # is the only one who knows whether this change qualifies, and next_action
  # has no way to ask it, so the sentence is unconditional on every gate0.
  local gate0_light=" if Propose classified this as a fast-path fix, also offer 'Accept — light lifecycle'"

  emit() { # emit action tier model reason [set_phase]
    printf 'action: %s\ntier: %s\nmodel: %s\n' "$1" "$2" "$3"
    [ -n "${5:-}" ] && printf 'set_phase: %s\n' "$5"
    printf 'reason: %s\n' "$4"
    emit_role_lines "$slug" "$1"
  }
  fix_tier() { # tier for fix round number (1-based)
    case "$1" in 1) echo standard ;; 2) echo standard ;; *) echo deep ;; esac
  }
  # A verify result of `spec` gates; once the human records
  # `spec_amend accepted` the fix round that rewrites the delta spec and
  # its checks is design work, so it runs at deep whatever the round number.
  spec_fix() {
    if [ "$fixes" -ge "$FIX_CAP" ]; then
      emit gate1 none - "spec amendment accepted but no fix rounds left ($fixes/$FIX_CAP)"
    else
      emit fix deep "$(model_for_tier "$slug" deep)" "spec amendment accepted at Gate 1, fix round $((fixes + 1))/$FIX_CAP at deep: amend the proposal/delta spec and the checks together, then clear spec_amend, last_gate_result and last_verify_result and recheck"
    fi
  }
  emit_effort() { [ -n "$ceffort" ] && printf 'effort: %s\n' "$ceffort"; return 0; }
  # not_converging <last> <prev>: both blocking and the count did not fall.
  # The other half of the convergence test (a closed finding reappearing)
  # needs finding ids in the reports and stays with the checker's judgement.
  not_converging() {
    case "$1:$2" in blocking:*:blocking:*) ;; *) return 1 ;; esac
    [ "${1#blocking:}" -ge "${2#blocking:}" ]
  }

  case "$phase" in
    blocked)
      emit wait none - "blocked on $blocked; resumes when it merges (merge trunk in first)" ;;
    proposed)
      case "$crit" in
        "")
          if [ -z "$(proposer_model "$slug" "$name")" ]; then
            # Shape before draft: classify, then grill unless trivial, then propose.
            if [ -z "$pillars" ]; then
              emit classify standard "$(model_for_tier "$slug" standard)" "no classification yet: read the request and the code, then record the four pillar readings with state set pillars 'scope=file|seam|seams;blast=none|project|public;novelty=known|new;deps=none|dev|runtime' — the critic grades these later, so read them for the code as it is"
            elif ! pillars_check "$pillars"; then
              return 1
            elif pillars_trivial "$pillars"; then
              emit propose "$ptier" "$(model_for_tier "$slug" "$ptier")" "trivial on every pillar ($pillars): grill mode skipped, Propose drafts the smallest delta spec at $ptier ($lc lifecycle)"
            elif [ "$grill" != done ] && [ "$grill" != skipped:human ]; then
              emit grill none - "not trivial ($pillars) and grill not yet run: run grill mode on this request now (SKILL.md Grill mode, in-change entry) — analysis round, then grilling and domain-modeling into the root's Project glossary and ADRs; then state set grill done. Autonomy starts after this: the human settles what and how here, the engine decides everything else"
            else
              emit propose "$ptier" "$(model_for_tier "$slug" "$ptier")" "classified ($pillars), grill $grill: Propose drafts at $ptier ($lc lifecycle) citing the Project glossary and ADRs"
            fi
          else
            emit critique "$(critic_tier "$slug" "$name")" "$(critic_model "$slug" "$name")" "draft exists, not yet critiqued: critic one tier above the proposer"
            emit_effort
          fi ;;
        clean|warnings:*)
          emit gate0 none - "critique passed ($crit); warnings swept at mechanical in place: ask the human to accept a short resume before Apply.$gate0_light" awaiting-acceptance ;;
        blocking:*)
          if not_converging "$crit" "$pcrit"; then
            emit gate1 none - "critique not converging: $pcrit -> $crit, blocking count did not fall; spending remaining rounds would repeat it"
          elif [ "$prounds" -ge "$PROPOSE_CAP" ]; then
            emit gate1 none - "critique still blocking after $prounds/$PROPOSE_CAP rounds: human clarifies the request"
          else
            emit revise "$ptier" "$(model_for_tier "$slug" "$ptier")" "critique $crit, round $((prounds + 1))/$PROPOSE_CAP: proposer revises only the named findings, then critique reruns"
          fi ;;
        request)
          emit gate1 none - "critique says the request itself is contradictory or ambiguous" ;;
        *) echo "unknown last_critique_result '$crit'" >&2; return 1 ;;
      esac ;;
    awaiting-acceptance)
      case "$accept" in
        "")
          emit gate0 none - "waiting on the human: show the short resume, offer the full proposal, and get accept or request-changes.$gate0_light" ;;
        accepted)
          emit apply none - "commit everything git status --porcelain shows in the change worktree, record phase applying, then call next: the split follows" applying ;;
        revise)
          emit propose "$ptier" "$(model_for_tier "$slug" "$ptier")" "human requested changes: restart Propose with the feedback file as new context; clear last_critique_result, prev_critique_result, propose_rounds and acceptance first, then critique reruns and a new resume is shown at Gate 0" proposed ;;
        *) echo "unknown acceptance '$accept' (expected accepted|revise)" >&2; return 1 ;;
      esac ;;
    applying)
      next_action_applying "$slug" "$name" "$f" "$lc" || return 1 ;;
    checking)
      case "$gate" in
        "")
          # Both are read-only readers of the committed tree, so they run
          # at once; the pass line (green AND clean) is unchanged.
          local cnote; cnote="$(verify_note "$slug" "$name")"
          emit check none - "run the full gate and Verify concurrently on the committed tree; record last_gate_result green|red and last_verify_result${cnote:+; verify $cnote}"
          local vm; vm="$(verify_model "$slug" "$name")" || vm=-
          printf 'also: verify\nalso_model: %s\n' "$vm"
          local vp; vp="$(role_prompt verifier)" || return 1
          printf 'also_prompt: %s\n' "$vp"
          local vov; vov="$(role_overlay "$slug" verifier)"
          [ -n "$vov" ] && printf 'also_overlay: %s\n' "$vov"
          printf 'also_agent: %s\n' "$(role_agent verifier)"
          emit_effort ;;
        red)
          if [ "$verify" = spec ] && [ "$spec_amend" = accepted ]; then
            spec_fix
          elif [ "$verify" = spec ]; then
            emit gate1 none - "verify says the proposal itself is wrong: human owns the spec; record spec_amend accepted to run the amendment as a deep fix round"
          elif [ -n "$verify" ] && not_converging "$verify" "$pverify"; then
            emit gate1 none - "verify not converging: $pverify -> $verify, blocking count did not fall; spending remaining rounds would repeat it"
          elif [ "$fixes" -ge "$FIX_CAP" ]; then
            emit gate1 none - "full gate red after $fixes/$FIX_CAP fix rounds"
          else
            local n=$((fixes + 1)); local t; t="$(fix_tier "$n")"
            emit fix "$t" "$(model_for_tier "$slug" "$t")" "gate red${verify:+; verify $verify}, fix round $n/$FIX_CAP (round 1 may drop to mechanical by triage): fix everything the gate${verify:+ and the verify report} name, then clear last_gate_result and last_verify_result and recheck"
          fi ;;
        green)
          case "$verify" in
            "")
              local vnote; vnote="$(verify_note "$slug" "$name")"
              emit verify "$(verify_tier "$slug" "$name")" "$(verify_model "$slug" "$name")" "gate green, not yet verified: checker one tier above the implementer${vnote:+; $vnote}"
              emit_effort ;;
            clean)
              emit tasks-open none - "verify clean: run 'tasks open' to record manual_tasks_open, then record verified" verified ;;
            warnings:*)
              if [ "$lc" = light ]; then
                emit tasks-open none - "light lifecycle: verify $verify, sweep skipped; run 'tasks open' to record manual_tasks_open, then record verified; list the warnings at Gate 2" verified
              else
                emit sweep mechanical "$(model_for_tier "$slug" mechanical)" "verify $verify: one mechanical sweep + quick gate, no re-verify, not a round; then set last_verify_result clean"
              fi ;;
            blocking:*)
              if not_converging "$verify" "$pverify"; then
                emit gate1 none - "verify not converging: $pverify -> $verify, blocking count did not fall; spending remaining rounds would repeat it"
              elif [ "$fixes" -ge "$FIX_CAP" ]; then
                emit gate1 none - "verify still blocking after $fixes/$FIX_CAP fix rounds"
              else
                local n=$((fixes + 1)); local t; t="$(fix_tier "$n")"
                emit fix "$t" "$(model_for_tier "$slug" "$t")" "verify $verify, fix round $n/$FIX_CAP: fix only the named findings, then clear last_gate_result and last_verify_result and recheck"
              fi ;;
            spec)
              if [ "$spec_amend" = accepted ]; then
                spec_fix
              else
                emit gate1 none - "verify says the proposal itself is wrong: human owns the spec; record spec_amend accepted to run the amendment as a deep fix round"
              fi ;;
            *) echo "unknown last_verify_result '$verify'" >&2; return 1 ;;
          esac ;;
        *) echo "unknown last_gate_result '$gate' (expected green|red)" >&2; return 1 ;;
      esac ;;
    verified)
      if [ -z "$manual_open" ]; then
        emit tasks-open none - "manual_tasks_open not yet counted: run 'tasks open' before archive can proceed"
      elif [ "$manual_open" -eq 0 ] 2>/dev/null; then
        emit archive none - "finalize artifacts and commit on the branch; --yes is allowed because the recorded manual_tasks_open count is 0" archived
      elif [ -n "$manual_accept" ]; then
        case "$manual_accept" in
          accepted:)
            echo "manual_accept 'accepted:' names no requirements" >&2; return 1 ;;
          accepted:*)
            emit archive none - "finalize artifacts and commit on the branch; --yes is allowed because the human accepted named unverified requirements ($manual_accept)" archived ;;
          *) echo "unknown manual_accept '$manual_accept' (expected accepted:<requirement>[;<requirement>...])" >&2; return 1 ;;
        esac
      else
        emit gate2-manual none - "manual_tasks_open: $manual_open open: show the human the open task list alongside the verify report; they tick each task then rerun 'tasks open', or record manual_accept naming the unverified requirements — never offer trying it after merge"
      fi ;;
    archived)
      emit merge-lane none - "merge trunk in under the merge lock and rerun the full gate; green -> ready-to-merge, red -> phase checking with last_gate_result red" ready-to-merge ;;
    ready-to-merge)
      local light_note=""
      [ "$lc" = light ] && light_note="; lifecycle light: also show the unswept Verify warnings"
      case "$manual_accept" in
        accepted:*)
          emit gate2 none - "ask the human with diffstat, gate log, verify report; accepted unverified requirements: ${manual_accept#accepted:}${light_note}; on approval squash-merge, record initiative merged, remove workspace, release slot" merged ;;
        *)
          emit gate2 none - "ask the human with diffstat, gate log, verify report${light_note}; on approval squash-merge, record initiative merged, remove workspace, release slot" merged ;;
      esac ;;
    merged)
      emit done none - "nothing left for this change" ;;
    *) echo "unknown phase '$phase'" >&2; return 1 ;;
  esac
}
