# Shared fixtures and assertions for tests/t-*.sh. Every file sources this,
# gets its own temp dir and registry, and so runs independently of the others.
# Tests stay black-box: they drive run-change through its CLI only.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
SKILL=skills/openspec-orchestrator
RC=$SKILL/scripts/run-change

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export OPENSPEC_STORE_REGISTRY="$TMP/registry.yaml"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
printf 'stores:\n' > "$OPENSPEC_STORE_REGISTRY"

fails=0
check() { # check <desc> <cmd...>
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then echo "ok   $desc"; else echo "FAIL $desc"; fails=$((fails+1)); fi
}
check_fails() { # check_fails <desc> <cmd...> -- the command must exit non-zero
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then echo "FAIL $desc (exit 0)"; fails=$((fails+1)); else echo "ok   $desc"; fi
}
check_out() { # check_out <desc> <expected-substring> <cmd...>
  local desc="$1" want="$2"; shift 2
  local out; out="$("$@" 2>&1)" || { echo "FAIL $desc (exit)"; fails=$((fails+1)); return; }
  case "$out" in *"$want"*) echo "ok   $desc" ;; *) echo "FAIL $desc (got: $out)"; fails=$((fails+1)) ;; esac
}
check_err() { # check_err <desc> <expected-substring> <cmd...> -- like check_out
  # but reads stderr too and ignores the exit status (for refusal messages)
  local desc="$1" want="$2"; shift 2
  local out; out="$("$@" 2>&1 || true)"
  case "$out" in *"$want"*) echo "ok   $desc" ;; *) echo "FAIL $desc (got: $out)"; fails=$((fails+1)) ;; esac
}
check_not() { # check_not <desc> <unwanted-substring> <cmd...>
  local desc="$1" bad="$2"; shift 2
  local out; out="$("$@" 2>&1 || true)"
  case "$out" in *"$bad"*) echo "FAIL $desc (got: $out)"; fails=$((fails+1)) ;; *) echo "ok   $desc" ;; esac
}
check_line() { # check_line <desc> <expected-exact-line> <cmd...> -- asserts
  # one of the command's output lines equals <expected-exact-line> exactly,
  # so a substring like "ready: " cannot pass against "ready: b".
  local desc="$1" want="$2"; shift 2
  local out; out="$("$@" 2>&1)" || { echo "FAIL $desc (exit)"; fails=$((fails+1)); return; }
  if printf '%s\n' "$out" | grep -qxF -- "$want"; then echo "ok   $desc"; else echo "FAIL $desc (got: $out)"; fails=$((fails+1)); fi
}
line_of() { # line_of <exact-line-or-prefix> <text> -> 1-based number of the
  # first line of <text> starting with it, empty if none
  printf '%s\n' "$2" | { grep -nF -- "$1" || true; } | while IFS=: read -r n l; do
    case "$l" in "$1"*) echo "$n"; break ;; esac
  done
}
finish() { [ "$fails" -eq 0 ] || exit 1; }

# register_store <slug> <path> -- registry entry only
register_store() { printf '  %s:\n    local_path: %s\n' "$1" "$2" >> "$OPENSPEC_STORE_REGISTRY"; }
# mkstore <slug> [path] <<config -> path; registers the store and writes
# <path>/openspec/config.yaml from stdin
mkstore() {
  local path="${2:-$TMP/$1}"
  mkdir -p "$path/openspec"
  cat > "$path/openspec/config.yaml"
  register_store "$1" "$path"
  echo "$path"
}
# mkproject <path> [file...] -- a local repo on main with one commit holding
# the named files (content = name)
mkproject() {
  local p="$1"; shift
  git init -q -b main "$p"
  for f in "$@"; do echo "$f" > "$p/$f"; done
  [ $# -gt 0 ] || echo hello > "$p/README"
  git -C "$p" add -A && git -C "$p" commit -qm init
}
# mkchange <store> <name> [key value ...] -- state init, then set the pairs
mkchange() {
  local store="$1" name="$2"; shift 2
  $RC state init --store "$store" --name "$name" >/dev/null
  [ $# -eq 0 ] || $RC state set --store "$store" --name "$name" "$@" >/dev/null
}

# the default external store: cap 2, echo gates that print their cwd
teststore() {
  STORE="$(mkstore teststore <<'EOF'
orchestration:
  concurrency: 2
  unit_concurrency: 2
  gate_quick: "echo QUICK-OK in $PWD"
  gate_full: "echo FULL-OK in $PWD"
EOF
)"
}
# PROJECT: a clone of a bare origin on main, for the merge lane and slots
mkorigin() {
  git init -q --bare -b main "$TMP/origin"
  git clone -q "$TMP/origin" "$TMP/project"
  PROJECT="$TMP/project"
  echo hello > "$PROJECT/README"
  git -C "$PROJECT" add -A && git -C "$PROJECT" commit -qm init && git -C "$PROJECT" push -q origin main
}
# teststore mapping standard, deep and max all onto one custom model, with
# critic and worker overlays: the fixture the next-ladder tests assume
pin_models_custom() {
  cat >> "$STORE/openspec/config.yaml" <<'EOF'
  model_standard: "claude-opus-5-custom"
  model_deep: "claude-opus-5-custom"
  model_max: "claude-opus-5-custom"
EOF
  mkdir -p "$STORE/openspec/roles"
  printf 'Check every scenario in the delta spec has a named test.\n' > "$STORE/openspec/roles/critic.md"
  printf 'Run tests with ./tests/run.sh; a red check prints FAIL.\n' > "$STORE/openspec/roles/worker.md"
}
